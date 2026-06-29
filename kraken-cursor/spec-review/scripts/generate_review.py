#!/usr/bin/env python3
"""
generate_review.py — Generate an interactive HTML review page for a markdown spec.

Supports both plain Markdown specs and Hybrid XML-Markdown specs
(using <context>, <constraints>, <task>, <output> blocks).

Usage:
    python generate_review.py <spec-path> <review-folder>

Outputs:
    <review-folder>/<spec-stem>-review.html   (auto-opened in browser)
"""

import sys
import os
import re
import json
import webbrowser
from pathlib import Path
from datetime import datetime


# ---------------------------------------------------------------------------
# Markdown helpers
# ---------------------------------------------------------------------------

def escape_html(text: str) -> str:
    return (text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;"))


def parse_frontmatter(content: str):
    """Strip YAML frontmatter and return (meta_dict, body)."""
    meta = {}
    if content.startswith("---"):
        end = content.find("---", 3)
        if end != -1:
            for line in content[3:end].split("\n"):
                if ":" in line:
                    k, _, v = line.partition(":")
                    meta[k.strip()] = v.strip()
            content = content[end + 3:].strip()
    return meta, content


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def md_inline(text: str) -> str:
    """Convert inline markdown (bold, italic, code, links) to HTML."""
    parts = re.split(r"`([^`]+)`", text)
    result = []
    for i, part in enumerate(parts):
        if i % 2 == 1:
            result.append(f"<code>{escape_html(part)}</code>")
        else:
            p = escape_html(part)
            p = re.sub(r"\*\*\*(.+?)\*\*\*", r"<strong><em>\1</em></strong>", p)
            p = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", p)
            p = re.sub(r"\*(.+?)\*", r"<em>\1</em>", p)
            p = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', p)
            result.append(p)
    return "".join(result)


def md_block(text: str) -> str:
    """Convert a markdown block (no headings) to HTML."""
    lines = text.split("\n")
    html_parts = []
    i = 0
    while i < len(lines):
        line = lines[i]

        # Fenced code block
        if line.startswith("```"):
            lang = line[3:].strip()
            code_lines = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                code_lines.append(escape_html(lines[i]))
                i += 1
            html_parts.append(
                f'<pre><code class="language-{escape_html(lang)}">'
                + "\n".join(code_lines)
                + "</code></pre>"
            )
            i += 1
            continue

        # Blockquote
        if line.startswith("> "):
            html_parts.append(f"<blockquote>{md_inline(line[2:])}</blockquote>")
            i += 1
            continue

        # Unordered list
        if re.match(r"^[-*+] ", line):
            items = []
            while i < len(lines) and re.match(r"^[-*+] ", lines[i]):
                items.append(f"<li>{md_inline(lines[i][2:])}</li>")
                i += 1
            html_parts.append("<ul>" + "".join(items) + "</ul>")
            continue

        # Ordered list
        if re.match(r"^\d+\. ", line):
            items = []
            while i < len(lines) and re.match(r"^\d+\. ", lines[i]):
                items.append(f"<li>{md_inline(re.sub(r'^\d+\. ', '', lines[i]))}</li>")
                i += 1
            html_parts.append("<ol>" + "".join(items) + "</ol>")
            continue

        # Horizontal rule
        if re.match(r"^-{3,}$|^\*{3,}$|^_{3,}$", line.strip()):
            html_parts.append("<hr>")
            i += 1
            continue

        # Table (simple)
        if "|" in line:
            table_lines = []
            while i < len(lines) and "|" in lines[i]:
                table_lines.append(lines[i])
                i += 1
            if table_lines:
                rows = []
                is_header = True
                for tl in table_lines:
                    if re.match(r"^\|[-| :]+\|$", tl.strip()):
                        continue
                    cells = [c.strip() for c in tl.strip().strip("|").split("|")]
                    tag = "th" if is_header else "td"
                    row_html = "".join(f"<{tag}>{md_inline(c)}</{tag}>" for c in cells)
                    rows.append(f"<tr>{row_html}</tr>")
                    is_header = False
                html_parts.append('<div class="table-wrap"><table>' + "".join(rows) + "</table></div>")
            continue

        # Blank line
        if not line.strip():
            i += 1
            continue

        # Regular paragraph
        html_parts.append(f"<p>{md_inline(line)}</p>")
        i += 1

    return "\n".join(html_parts)


# ---------------------------------------------------------------------------
# XML-Markdown hybrid support
# ---------------------------------------------------------------------------

XML_TAGS = {"context", "constraints", "task", "output"}

XML_META = {
    "context":     {"icon": "🧭", "label": "Context",     "callout": "xml-context"},
    "constraints": {"icon": "🔒", "label": "Constraints", "callout": "xml-constraints"},
    "task":        {"icon": "🎯", "label": "Task",        "callout": "xml-task"},
    "output":      {"icon": "📤", "label": "Output",      "callout": "xml-output"},
}


def has_xml_blocks(body: str) -> bool:
    """Return True if the body contains any recognised XML block tags."""
    return bool(re.search(
        r"^<(?:context|constraints|task|output)>\s*$",
        body, re.IGNORECASE | re.MULTILINE
    ))


def parse_sections(body: str):
    """
    Split body into section dicts, handling both:
      - Markdown headings  (## Heading)
      - XML block tags     (<context> ... </context>)
    """
    sections = []
    current = {"level": 0, "title": "__preamble__", "id": "__preamble__", "lines": [], "xml_type": None}

    lines = body.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]

        # ── Markdown heading ──────────────────────────────────────────────
        m = re.match(r"^(#{1,6})\s+(.+)$", line)
        if m:
            if current["lines"] or current["title"] != "__preamble__":
                current["content"] = "\n".join(current["lines"])
                sections.append(current)
            level = len(m.group(1))
            title = m.group(2)
            current = {"level": level, "title": title, "id": slugify(title), "lines": [], "xml_type": None}
            i += 1
            continue

        # ── XML opening tag ───────────────────────────────────────────────
        xml_open = re.match(r"^<(context|constraints|task|output)>\s*$", line, re.IGNORECASE)
        if xml_open:
            tag_name = xml_open.group(1).lower()
            # flush whatever came before
            if current["lines"] or current["title"] != "__preamble__":
                current["content"] = "\n".join(current["lines"])
                sections.append(current)

            # collect lines until closing tag
            xml_lines = []
            i += 1
            close_pattern = re.compile(rf"^</{re.escape(tag_name)}>\s*$", re.IGNORECASE)
            while i < len(lines) and not close_pattern.match(lines[i]):
                xml_lines.append(lines[i])
                i += 1
            if i < len(lines):
                i += 1  # skip closing tag

            meta = XML_META[tag_name]
            xml_section = {
                "level": 2,
                "title": f"{meta['icon']} {meta['label']}",
                "id": slugify(tag_name),
                "lines": xml_lines,
                "content": "\n".join(xml_lines),
                "xml_type": tag_name,
            }
            sections.append(xml_section)
            # reset accumulator
            current = {"level": 0, "title": "__preamble__", "id": f"post-{tag_name}", "lines": [], "xml_type": None}
            continue

        current["lines"].append(line)
        i += 1

    current["content"] = "\n".join(current["lines"])
    sections.append(current)
    return sections


# ---------------------------------------------------------------------------
# Callout helpers
# ---------------------------------------------------------------------------

CALLOUT_MAP = {
    "goal": "goal", "goals": "goal", "objective": "goal", "objectives": "goal",
    "risk": "risk", "risks": "risk", "concern": "risk", "concerns": "risk",
    "open question": "question", "open questions": "question",
    "question": "question", "questions": "question", "unknowns": "question",
    "decision": "decision", "decisions": "decision", "decision record": "decision",
    "assumption": "assumption", "assumptions": "assumption",
    "non-goal": "risk", "non-goals": "risk", "out of scope": "risk",
}


def callout_type(section: dict):
    """Return a CSS callout class for the section, or None."""
    if section.get("xml_type"):
        return XML_META[section["xml_type"]]["callout"]
    tl = section["title"].lower()
    for key, cat in CALLOUT_MAP.items():
        if key in tl:
            return cat
    return None


# ---------------------------------------------------------------------------
# HTML generation
# ---------------------------------------------------------------------------

def build_html(spec_path: Path, meta: dict, sections: list, spec_title: str, is_hybrid: bool) -> str:
    visible = [s for s in sections if s["level"] > 0]
    total = len(visible)

    # --- TOC ---
    toc_items = []
    for s in visible:
        indent = (s["level"] - 1) * 14
        toc_items.append(
            f'<li style="padding-left:{indent}px">'
            f'<a href="#{s["id"]}" onclick="scrollTo(\'{s["id"]}\')">'
            f'{escape_html(s["title"])}</a></li>'
        )

    # --- Sections ---
    section_divs = []
    for s in visible:
        ct = callout_type(s)
        callout_cls = f" callout callout-{ct}" if ct else ""
        ht = f"h{min(s['level'] + 1, 5)}"
        body_html = md_block(s["content"])

        # XML badge
        xml_badge = ""
        if s.get("xml_type"):
            xml_badge = f'<span class="xml-badge xml-badge-{s["xml_type"]}">&lt;{s["xml_type"]}&gt;</span>'

        section_divs.append(f"""
<div class="section{callout_cls}" id="{s['id']}">
  <div class="section-header">
    <{ht}>{escape_html(s['title'])}{xml_badge}</{ht}>
    <label class="check-label">
      <input type="checkbox" class="section-check" data-section="{s['id']}" onchange="updateProgress()">
      <span>Looks good</span>
    </label>
  </div>
  <div class="section-body">{body_html}</div>
  <div class="section-comment">
    <textarea placeholder="Notes / questions for this section..."
              data-section="{s['id']}"
              oninput="saveDraft()" rows="2"></textarea>
  </div>
</div>""")

    date_str = meta.get("date", "")
    author_str = meta.get("author", meta.get("authors", ""))
    format_badge = '🔀 Hybrid XML-MD' if is_hybrid else '📝 Markdown'
    meta_badges = f'<span class="meta-badge">📄 {escape_html(spec_path.name)}</span>'
    meta_badges += f' <span class="meta-badge">{format_badge}</span>'
    if date_str:
        meta_badges += f' <span class="meta-badge">📅 {escape_html(date_str)}</span>'
    if author_str:
        meta_badges += f' <span class="meta-badge">👤 {escape_html(author_str)}</span>'

    toc_html = "\n".join(toc_items)
    sections_html = "\n".join(section_divs)
    spec_title_esc = escape_html(spec_title)
    spec_file_json = json.dumps(spec_path.name)
    spec_title_json = json.dumps(spec_title)
    total_json = json.dumps(total)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Review: {spec_title_esc}</title>
<style>
:root {{
  --bg: #0f1117; --surface: #1a1d27; --surface2: #21253a; --border: #2e3247;
  --text: #e2e4ef; --muted: #8b8fa8; --accent: #6c8ef5;
  --green: #4caf8a; --red: #e05c6a; --yellow: #f0b429;
  --orange: #f07a29; --purple: #9b72f5;
  --xml-context: #4db6e0;
  --xml-constraints: #e05c6a;
  --xml-task: #6c8ef5;
  --xml-output: #4caf8a;
}}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
       background: var(--bg); color: var(--text); display: flex; min-height: 100vh; }}

/* ── Sidebar ── */
#sidebar {{ width: 268px; min-width: 268px; background: var(--surface);
            border-right: 1px solid var(--border); padding: 24px 16px;
            position: sticky; top: 0; height: 100vh; overflow-y: auto;
            display: flex; flex-direction: column; gap: 20px; }}
#sidebar h3 {{ font-size: 10px; text-transform: uppercase; letter-spacing: .1em;
               color: var(--muted); margin-bottom: 6px; }}
#toc {{ list-style: none; }}
#toc li {{ margin: 3px 0; }}
#toc a {{ color: var(--muted); text-decoration: none; font-size: 12.5px;
          line-height: 1.45; display: block; padding: 2px 6px; border-radius: 4px;
          transition: all .15s; }}
#toc a:hover {{ color: var(--text); background: var(--surface2); }}
#progress-bar-wrap {{ background: var(--border); border-radius: 4px; height: 6px; overflow: hidden; }}
#progress-bar {{ height: 100%; background: var(--green); border-radius: 4px;
                 transition: width .3s; width: 0%; }}
#progress-label {{ font-size: 12px; color: var(--muted); margin-top: 5px; }}
.action-buttons {{ display: flex; flex-direction: column; gap: 8px;
                   margin-top: auto; padding-top: 16px; border-top: 1px solid var(--border); }}
#status-badge {{ display: inline-block; padding: 4px 14px; border-radius: 12px;
                 font-size: 12px; font-weight: 600; background: var(--surface2);
                 color: var(--muted); border: 1px solid var(--border); text-align: center; }}
#status-badge.approved {{ background: rgba(76,175,138,.15); color: var(--green); border-color: var(--green); }}
#status-badge.changes  {{ background: rgba(224,92,106,.15);  color: var(--red);   border-color: var(--red);   }}

/* ── Buttons ── */
.btn {{ padding: 10px 16px; border-radius: 8px; border: none; font-size: 13.5px;
        font-weight: 600; cursor: pointer; transition: all .15s; text-align: center; width: 100%; }}
.btn-approve {{ background: var(--green); color: #fff; }}
.btn-approve:hover {{ filter: brightness(1.12); }}
.btn-changes {{ background: var(--surface2); color: var(--text); border: 1px solid var(--border); }}
.btn-changes:hover {{ border-color: var(--red); color: var(--red); }}
.btn-copy {{ background: transparent; color: var(--muted); border: 1px solid var(--border); font-size: 12px; }}
.btn-copy:hover {{ color: var(--text); border-color: var(--text); }}

/* ── Main ── */
#main {{ flex: 1; padding: 36px 52px; max-width: 880px; }}
.spec-header {{ margin-bottom: 32px; padding-bottom: 24px; border-bottom: 1px solid var(--border); }}
.spec-header h1 {{ font-size: 26px; font-weight: 700; line-height: 1.35; margin-bottom: 10px; }}
.spec-meta {{ display: flex; flex-wrap: wrap; gap: 8px; font-size: 12.5px; color: var(--muted); }}
.meta-badge {{ background: var(--surface2); padding: 2px 10px; border-radius: 12px;
               border: 1px solid var(--border); }}

/* ── Sections ── */
.section {{ margin-bottom: 28px; padding: 20px 24px; background: var(--surface);
            border-radius: 10px; border: 1px solid var(--border); transition: border-color .2s; }}
.section:has(.section-check:checked) {{
  border-color: var(--green); background: rgba(76,175,138,.04); }}
.section-header {{ display: flex; align-items: flex-start; justify-content: space-between;
                   margin-bottom: 14px; gap: 14px; }}
.section-header h2 {{ font-size: 18px; font-weight: 600; }}
.section-header h3 {{ font-size: 15.5px; font-weight: 600; }}
.section-header h4, .section-header h5 {{ font-size: 14px; font-weight: 600; }}
.check-label {{ display: flex; align-items: center; gap: 6px; font-size: 12px;
                color: var(--muted); cursor: pointer; white-space: nowrap;
                padding: 4px 10px; border-radius: 6px; border: 1px solid var(--border);
                transition: all .15s; flex-shrink: 0; }}
.check-label:hover {{ border-color: var(--green); color: var(--green); }}
.section-check:checked + span {{ color: var(--green); font-weight: 600; }}
.section-check {{ accent-color: var(--green); width: 14px; height: 14px; }}

/* ── Body typography ── */
.section-body {{ font-size: 14px; line-height: 1.75; color: var(--text); }}
.section-body p {{ margin-bottom: 12px; }}
.section-body ul, .section-body ol {{ padding-left: 22px; margin-bottom: 12px; }}
.section-body li {{ margin-bottom: 5px; }}
.section-body pre {{ background: var(--bg); border: 1px solid var(--border);
                     border-radius: 6px; padding: 14px 16px; overflow-x: auto;
                     margin-bottom: 12px; }}
.section-body code {{ font-family: 'JetBrains Mono','Fira Code',monospace; font-size: 12.5px; }}
.section-body :not(pre) > code {{ background: var(--surface2); padding: 1px 5px;
                                   border-radius: 3px; font-size: 12px; }}
.section-body blockquote {{ border-left: 3px solid var(--accent); padding-left: 16px;
                             color: var(--muted); font-style: italic; margin-bottom: 12px; }}
.section-body strong {{ color: #fff; }}
.section-body a {{ color: var(--accent); }}
.section-body hr {{ border: none; border-top: 1px solid var(--border); margin: 14px 0; }}
.section-body h2,.section-body h3,.section-body h4,.section-body h5 {{
  font-weight: 600; margin: 16px 0 8px; color: var(--text); }}
.section-body h2 {{ font-size: 16px; }}
.section-body h3 {{ font-size: 14.5px; }}
.section-body h4 {{ font-size: 13.5px; }}
.table-wrap {{ overflow-x: auto; margin-bottom: 12px; }}
table {{ border-collapse: collapse; width: 100%; font-size: 13px; }}
th, td {{ border: 1px solid var(--border); padding: 7px 12px; text-align: left; }}
th {{ background: var(--surface2); font-weight: 600; }}

/* ── Section comments ── */
.section-comment {{ margin-top: 14px; }}
.section-comment textarea {{ width: 100%; background: var(--bg); border: 1px solid var(--border);
  border-radius: 6px; color: var(--text); font-size: 13px; padding: 8px 12px;
  resize: vertical; font-family: inherit; transition: border-color .15s; }}
.section-comment textarea:focus {{ outline: none; border-color: var(--accent); }}
.section-comment textarea:not(:placeholder-shown) {{ border-color: var(--yellow); }}

/* ── Markdown callout accents ── */
.callout-goal       {{ border-left: 4px solid var(--green); }}
.callout-risk       {{ border-left: 4px solid var(--red); }}
.callout-question   {{ border-left: 4px solid var(--yellow); }}
.callout-decision   {{ border-left: 4px solid var(--purple); }}
.callout-assumption {{ border-left: 4px solid var(--orange); }}

/* ── XML block callout accents ── */
.callout-xml-context     {{ border-left: 4px solid var(--xml-context);     background: rgba(77,182,224,.04); }}
.callout-xml-constraints {{ border-left: 4px solid var(--xml-constraints); background: rgba(224,92,106,.04); }}
.callout-xml-task        {{ border-left: 4px solid var(--xml-task);        background: rgba(108,142,245,.04); }}
.callout-xml-output      {{ border-left: 4px solid var(--xml-output);      background: rgba(76,175,138,.04); }}

/* ── XML badge pill ── */
.xml-badge {{
  display: inline-block; margin-left: 10px; padding: 1px 8px;
  border-radius: 10px; font-size: 10px; font-family: 'JetBrains Mono','Fira Code',monospace;
  font-weight: 600; vertical-align: middle; opacity: 0.75;
}}
.xml-badge-context     {{ background: rgba(77,182,224,.15);  color: var(--xml-context);     border: 1px solid var(--xml-context); }}
.xml-badge-constraints {{ background: rgba(224,92,106,.15);  color: var(--xml-constraints); border: 1px solid var(--xml-constraints); }}
.xml-badge-task        {{ background: rgba(108,142,245,.15); color: var(--xml-task);        border: 1px solid var(--xml-task); }}
.xml-badge-output      {{ background: rgba(76,175,138,.15);  color: var(--xml-output);      border: 1px solid var(--xml-output); }}

/* ── Toast ── */
#toast {{ position: fixed; bottom: 24px; right: 24px; background: var(--surface2);
          border: 1px solid var(--border); color: var(--text); padding: 12px 20px;
          border-radius: 8px; font-size: 13.5px; opacity: 0; transform: translateY(8px);
          transition: all .3s; pointer-events: none; z-index: 1000; max-width: 360px; }}
#toast.show {{ opacity: 1; transform: translateY(0); }}
</style>
</head>
<body>

<nav id="sidebar">
  <div>
    <h3>Contents</h3>
    <ul id="toc">{toc_html}</ul>
  </div>
  <div>
    <h3>Review Progress</h3>
    <div id="progress-bar-wrap"><div id="progress-bar"></div></div>
    <div id="progress-label">0 of {total} sections checked</div>
  </div>
  <div class="action-buttons">
    <div style="text-align:center;margin-bottom:6px">
      <span id="status-badge">⏳ Pending Review</span>
    </div>
    <button class="btn btn-approve" onclick="submitReview('approved')">
      ✅ Approve — Proceed to Implementation
    </button>
    <button class="btn btn-changes" onclick="submitReview('changes')">
      ⚠️ Request Changes
    </button>
    <button class="btn btn-copy" onclick="copyFeedback()">
      📋 Copy Feedback as Markdown
    </button>
  </div>
</nav>

<main id="main">
  <div class="spec-header">
    <h1>{spec_title_esc}</h1>
    <div class="spec-meta">{meta_badges}</div>
  </div>
  {sections_html}
</main>

<div id="toast"></div>

<script>
const SPEC_FILE  = {spec_file_json};
const SPEC_TITLE = {spec_title_json};
const TOTAL      = {total_json};
const STORAGE_KEY = 'spec-review-' + SPEC_FILE;

function scrollTo(id) {{
  const el = document.getElementById(id);
  if (el) el.scrollIntoView({{ behavior: 'smooth', block: 'start' }});
}}

function updateProgress() {{
  const checked = document.querySelectorAll('.section-check:checked').length;
  const pct = TOTAL ? (checked / TOTAL * 100) : 0;
  document.getElementById('progress-bar').style.width = pct + '%';
  document.getElementById('progress-label').textContent =
    checked + ' of ' + TOTAL + ' sections checked';
  saveDraft();
}}

function saveDraft() {{
  const data = {{ sections: {{}} }};
  document.querySelectorAll('.section-check').forEach(cb => {{
    const id = cb.dataset.section;
    const ta = document.querySelector('textarea[data-section="' + id + '"]');
    data.sections[id] = {{ checked: cb.checked, comment: ta ? ta.value : '' }};
  }});
  try {{ localStorage.setItem(STORAGE_KEY, JSON.stringify(data)); }} catch(e) {{}}
}}

function loadDraft() {{
  try {{
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const data = JSON.parse(raw);
    Object.entries(data.sections || {{}}).forEach(([id, val]) => {{
      const cb = document.querySelector('.section-check[data-section="' + id + '"]');
      const ta = document.querySelector('textarea[data-section="' + id + '"]');
      if (cb) cb.checked = val.checked;
      if (ta) ta.value   = val.comment || '';
    }});
    updateProgress();
  }} catch(e) {{}}
}}

function buildMarkdown(status) {{
  const statusLabel = status === 'approved' ? '✅ Approved' : '⚠️ Changes Requested';
  const lines = [
    '# Spec Review: ' + SPEC_TITLE,
    '**Status:** ' + statusLabel,
    ''
  ];
  let hasComments = false;
  document.querySelectorAll('.section').forEach(sec => {{
    const title = (sec.querySelector('h2,h3,h4,h5') || {{}}).textContent || sec.id;
    const ta    = sec.querySelector('textarea');
    const comment = ta && ta.value.trim();
    if (comment) {{
      lines.push('## ' + title);
      lines.push(comment);
      lines.push('');
      hasComments = true;
    }}
  }});
  if (!hasComments) lines.push('_No section comments — all looks good._');
  return lines.join('\\n');
}}

function submitReview(status) {{
  const badge = document.getElementById('status-badge');
  if (status === 'approved') {{
    badge.textContent = '✅ Approved';
    badge.className   = 'approved';
  }} else {{
    badge.textContent = '⚠️ Changes Requested';
    badge.className   = 'changes';
  }}
  const md = buildMarkdown(status);
  navigator.clipboard.writeText(md)
    .then(() => showToast(
      status === 'approved'
        ? '✅ Approved! Feedback copied — paste it back into Claude.'
        : '⚠️ Changes noted! Paste the feedback back into Claude.'
    ))
    .catch(() => showToast('Review set. Use the Copy button to grab the markdown.'));
  saveDraft();
}}

function copyFeedback() {{
  const badge  = document.getElementById('status-badge');
  const status = badge.classList.contains('approved') ? 'approved'
               : badge.classList.contains('changes')  ? 'changes' : 'pending';
  navigator.clipboard.writeText(buildMarkdown(status))
    .then(() => showToast('📋 Feedback copied to clipboard!'))
    .catch(() => showToast('Could not access clipboard. Try right-click copy.'));
}}

function showToast(msg) {{
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 4500);
}}

loadDraft();
</script>
</body>
</html>"""


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 3:
        print("Usage: generate_review.py <spec-path> <review-folder>")
        sys.exit(1)

    spec_path = Path(sys.argv[1]).resolve()
    review_folder = Path(sys.argv[2]).resolve()

    if not spec_path.exists():
        print(f"ERROR: Spec file not found: {spec_path}", file=sys.stderr)
        sys.exit(1)

    review_folder.mkdir(parents=True, exist_ok=True)

    content = spec_path.read_text(encoding="utf-8")
    meta, body = parse_frontmatter(content)

    is_hybrid = has_xml_blocks(body)

    # Title: first H1 in body, or prettify filename
    title_match = re.search(r"^# (.+)$", body, re.MULTILINE)
    spec_title = title_match.group(1).strip() if title_match else (
        spec_path.stem.replace("-", " ").replace("_", " ").title()
    )

    sections = parse_sections(body)
    html = build_html(spec_path, meta, sections, spec_title, is_hybrid)

    output_path = review_folder / (spec_path.stem + "-review.html")
    output_path.write_text(html, encoding="utf-8")

    fmt = "Hybrid XML-Markdown" if is_hybrid else "Markdown"
    print(f"Format detected : {fmt}")
    print(f"Review page     : {output_path}")
    webbrowser.open(output_path.as_uri())


if __name__ == "__main__":
    main()
