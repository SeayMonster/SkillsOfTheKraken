---
name: kraken-cursor-spec-review
description: >-
  Generates an interactive HTML review page for committed design specs so the user can visually
  read, annotate per-section, and formally approve or request changes before implementation begins.
  Trigger whenever the user says "spec committed", mentions a spec file path for review, shares a
  markdown spec and asks for feedback before writing an implementation plan, or says anything like
  "review this before I dispatch agents". Even if they don't say "spec reviewer" — if a .md spec
  file has just landed and they want eyes on it, this skill applies.
---

# kraken-cursor: spec-review

**Announce at start:** "I'm using kraken-cursor-spec-review to build the spec review page."

Turn a committed markdown spec into an interactive HTML review page the user can click through in their browser — then wait for them to approve or request changes.

## What the review page provides

- **Table of contents** in the sidebar with jump links
- **Per-section checkboxes** ("Looks good") + free-text comment boxes
- **Progress bar** showing how many sections have been checked off
- **Callout styling** for sections whose titles match: Goals, Risks, Open Questions, Decisions, Assumptions
- **Approve / Request Changes** buttons that copy a formatted markdown summary to the clipboard
- **Draft persistence** via localStorage — refreshing the page restores all checkboxes and comments

## Pre-flight

1. Resolve `SKILL_DIR` = directory containing this SKILL.md (installed at `~/.cursor/skills/kraken-cursor-spec-review/` or repo `kraken-cursor/spec-review/`).
2. Find the spec file from the user's path. If none provided, search for recently modified `.md` files under `docs/**/specs/` in `{repoRoot}`.

## Steps

### 1. Determine the review folder

Create `<spec-parent-dir>/review/` if it doesn't exist. For example, if the spec is at `docs/superpowers/specs/my-spec.md`, the review folder is `docs/superpowers/specs/review/`.

### 2. Run the bundled script

```bash
python "{SKILL_DIR}/scripts/generate_review.py" "<spec-path>" "<review-folder>"
```

The script writes `<review-folder>/<spec-stem>-review.html`. It may also attempt to open the default system browser; prefer Cursor browser MCP regardless (next step).

### 3. Open in Cursor browser

Use the **cursor-ide-browser** MCP server. Read tool schemas under the MCP descriptors before calling.

1. `browser_navigate` — open the generated HTML file URI (`file:///` path to `<review-folder>/<spec-stem>-review.html`).
2. `browser_lock` with `action: "lock"` — lock the tab after navigate.
3. `browser_snapshot` — confirm the review page loaded (sidebar TOC, section checkboxes).
4. `browser_lock` with `action: "unlock"` — release when done.

Do **not** use Claude-only browser MCP servers; use cursor-ide-browser only.

### 4. Tell the user

Say something like:

> Review page is open at `<review-folder>/<spec-name>-review.html`. Check off sections as you read, add any notes in the comment boxes, then click **Approve** or **Request Changes** — both buttons copy the feedback markdown to your clipboard so you can paste it back here.

## Output

Saved as `<review-folder>/<spec-stem>-review.html`. Dark-themed, self-contained single file.

## Related

- Claude Code equivalent: Use kraken spec-review (source skill `skills/spec-review/`)
