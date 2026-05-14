"""
Plugin Digest — fetch top Claude plugins from GitHub, generate HTML digest,
serve locally for one-click install.

Usage:
    python fetch_and_generate.py          # fetch fresh + open browser
    python fetch_and_generate.py --cached # use cached results (skip GitHub)
"""
import json
import pathlib
import sys
import urllib.request
import urllib.parse
import urllib.error
import html as _html
from datetime import datetime

CLAUDE_DIR = pathlib.Path.home() / ".claude"
DIGEST_HTML = CLAUDE_DIR / "plugin-digest.html"
DIGEST_CACHE = CLAUDE_DIR / "plugin-digest-cache.json"
INSTALLED_PLUGINS_PATH = CLAUDE_DIR / "plugins" / "installed_plugins.json"

GITHUB_SEARCH_TOPICS = ["claude-plugin", "claude-skill", "claude-code-plugin", "claude-code-skills"]
GITHUB_SEARCH_KEYWORDS = ["claude code skills", "claude code plugin"]
GITHUB_API = "https://api.github.com"


class RateLimitError(Exception):
    """Raised when the GitHub API returns a 403 rate-limit response."""


def _github_get(path: str) -> dict:
    """Make an unauthenticated GitHub API GET request."""
    url = f"{GITHUB_API}{path}"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
                                                "User-Agent": "plugin-digest/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 403:
            raise RateLimitError("GitHub API rate limit exceeded")
        raise


def search_github_plugins() -> list[dict]:
    """Search GitHub for Claude plugin repos across topics and keywords."""
    results = []

    # Topic searches
    for topic in GITHUB_SEARCH_TOPICS:
        try:
            data = _github_get(f"/search/repositories?q=topic:{topic}&sort=stars&per_page=30")
            results.extend(data.get("items", []))
        except RateLimitError:
            break
        except Exception as e:
            print(f"Warning: topic search failed for {topic}: {e}")
            continue

    # Keyword searches
    for keyword in GITHUB_SEARCH_KEYWORDS:
        try:
            encoded = urllib.parse.quote(keyword)
            data = _github_get(f"/search/repositories?q={encoded}&sort=stars&per_page=20")
            results.extend(data.get("items", []))
        except RateLimitError:
            break
        except Exception as e:
            print(f"Warning: keyword search failed for '{keyword}': {e}")
            continue

    return results


def get_known_marketplace_repos() -> list[dict]:
    """Read extraKnownMarketplaces from settings.json and return as repo dicts."""
    settings_path = CLAUDE_DIR / "settings.json"
    if not settings_path.exists():
        return []
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        marketplaces = settings.get("extraKnownMarketplaces", {})
        repos = []
        for _key, val in marketplaces.items():
            source = val.get("source", {}) if isinstance(val, dict) else {}
            source = source if isinstance(source, dict) else {}
            repo_name = source.get("repo")
            if repo_name:
                try:
                    data = _github_get(f"/repos/{repo_name}")
                    repos.append(data)
                except Exception:
                    continue
        return repos
    except Exception:
        return []


def deduplicate_repos(repos: list[dict]) -> list[dict]:
    """Remove duplicate repos by full_name."""
    seen = set()
    result = []
    for repo in repos:
        name = repo.get("full_name", "")
        if name and name not in seen:
            seen.add(name)
            result.append(repo)
    return result


def rank_by_stars(repos: list[dict], top_n: int = 10) -> list[dict]:
    """Sort repos by stargazers_count descending, return top_n."""
    sorted_repos = sorted(repos, key=lambda r: r.get("stargazers_count", 0), reverse=True)
    return sorted_repos[:top_n]


def get_installed_plugins(installed_path: pathlib.Path = None) -> dict:
    """
    Read installed_plugins.json and return a flat dict of
    {plugin_key: {version, installPath}} for the latest entry of each plugin.
    """
    path = installed_path or INSTALLED_PLUGINS_PATH
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        plugins = data.get("plugins", {})
        result = {}
        for key, entries in plugins.items():
            if entries:
                latest = entries[-1]  # last entry is most recent
                result[key] = {"version": latest.get("version", "unknown"),
                               "installPath": latest.get("installPath", "")}
        return result
    except Exception:
        return {}


def get_installed_repo_names(installed: dict) -> set[str]:
    """
    Extract lowercased repo-like names from installed plugin installPaths
    so we can match against GitHub full_name values.
    """
    names = set()
    for _key, val in installed.items():
        install_path = val.get("installPath", "")
        # installPath pattern: ...cache/<marketplace>/<plugin>/<version>
        parts = pathlib.Path(install_path).parts
        if len(parts) >= 2:
            # Use marketplace+plugin as a key to match GitHub repos
            idx = [i for i, p in enumerate(parts) if p == "cache"]
            if idx:
                cache_idx = idx[-1]
                if cache_idx + 2 < len(parts):
                    marketplace = parts[cache_idx + 1].lower()
                    plugin = parts[cache_idx + 2].lower()
                    names.add(f"{marketplace}/{plugin}")
    return names


def get_plugin_repo_key(full_name: str) -> str:
    """Normalize a GitHub full_name for comparison."""
    return full_name.lower()


def filter_uninstalled(repos: list[dict], installed_repos: set[str]) -> list[dict]:
    """Return only repos that are NOT already installed."""
    installed_lower = {r.lower() for r in installed_repos}
    return [r for r in repos
            if get_plugin_repo_key(r.get("full_name", "")) not in installed_lower]


def generate_html(top10: list[dict], needs_update: list[dict], port: int) -> str:
    """Generate the full plugin digest HTML page."""

    def card_html(repo: dict, rank: int) -> str:
        name = _html.escape(repo["full_name"].split("/")[-1])
        full_name = repo["full_name"]
        stars = f"★ {repo.get('stargazers_count', 0):,}"
        desc = _html.escape(repo.get("description", "No description.") or "No description.")
        marketplace = _html.escape(repo.get("_marketplace", repo["full_name"].split("/")[0]))
        top3_cls = " top3-card" if rank <= 3 else ""
        rank_cls = " top3" if rank <= 3 else ""
        encoded = urllib.parse.quote(full_name)
        return f"""
  <div class="card{top3_cls}" onclick="toggle(this)">
    <input type="checkbox" class="cb" data-repo="{full_name}">
    <div class="rank{rank_cls}">{rank}</div>
    <div class="card-body">
      <div class="card-top">
        <div class="plugin-name">{name}</div>
        <div class="stars">{stars}</div>
      </div>
      <div class="marketplace">{marketplace}</div>
      <div class="desc">{desc}</div>
    </div>
  </div>"""

    def update_card_html(item: dict) -> str:
        name = _html.escape(item["full_name"].split("/")[-1])
        full_name = item["full_name"]
        encoded = urllib.parse.quote(full_name)
        return f"""
  <div class="card update-card">
    <div class="rank">↑</div>
    <div class="card-body">
      <div class="card-top">
        <div class="plugin-name">{name}</div>
        <button class="update-btn" onclick="doUpdate('{encoded}', this)">Update</button>
      </div>
      <div class="desc">{_html.escape(item.get('description', ''))}</div>
      <div class="version-info">{item['installed_version']} → {item['latest_version']}</div>
    </div>
  </div>"""

    top10_cards = "\n".join(card_html(r, i + 1) for i, r in enumerate(top10))
    update_cards = "\n".join(update_card_html(u) for u in needs_update)
    updates_section = f"""
<h2 class="section-title">Needs Update</h2>
<div class="grid">{update_cards}</div>""" if needs_update else ""

    now = datetime.now()
    date_str = now.strftime("%A, %B") + f" {now.day}, {now.year}"
    count = len(top10)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Claude Plugin Digest</title>
<style>
  :root {{ --bg:#0f1117; --surface:#1a1d27; --surface2:#21253a; --border:#2e3247;
           --text:#e2e4ef; --muted:#8b8fa8; --accent:#6c8ef5;
           --green:#4caf8a; --yellow:#f0b429; }}
  * {{ box-sizing:border-box; margin:0; padding:0; }}
  body {{ font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
          background:var(--bg); color:var(--text); padding:2rem;
          max-width:960px; margin:0 auto; }}
  .header {{ display:flex; justify-content:space-between; align-items:flex-start;
             margin-bottom:1.5rem; padding-bottom:1.25rem; border-bottom:1px solid var(--border); }}
  .header h1 {{ font-size:1.4rem; font-weight:700; }}
  .meta {{ font-size:.8rem; color:var(--muted); margin-top:.3rem; }}
  .install-btn {{ background:var(--green); color:#fff; border:none; border-radius:8px;
                  padding:9px 20px; font-size:.85rem; font-weight:600; cursor:pointer; }}
  .install-btn:disabled {{ background:var(--border); color:var(--muted); cursor:default; }}
  .hint {{ background:var(--surface); border:1px solid var(--border); border-radius:8px;
           padding:.75rem 1rem; margin-bottom:1.5rem; font-size:.85rem; color:var(--muted);
           display:flex; justify-content:space-between; align-items:center; }}
  .section-title {{ font-size:1rem; font-weight:700; color:var(--muted); margin:2rem 0 1rem;
                    text-transform:uppercase; letter-spacing:.08em; font-size:.75rem; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(420px,1fr)); gap:1rem; }}
  .card {{ background:var(--surface); border:1px solid var(--border); border-radius:10px;
           padding:1rem 1.25rem; display:flex; gap:1rem; align-items:flex-start;
           transition:border-color .15s; cursor:pointer; }}
  .card:hover {{ border-color:var(--accent); }}
  .card.selected {{ border-color:var(--green); background:rgba(76,175,138,.05); }}
  .card.top3-card {{ border-color:var(--yellow); box-shadow:0 0 0 1px rgba(240,180,41,.2); }}
  .card.top3-card:hover {{ filter:brightness(1.05); }}
  .card.update-card {{ cursor:default; }}
  .rank {{ font-size:1.1rem; font-weight:800; color:var(--muted); min-width:26px;
           text-align:center; padding-top:2px; }}
  .rank.top3 {{ color:var(--yellow); }}
  .card-body {{ flex:1; }}
  .card-top {{ display:flex; justify-content:space-between; align-items:flex-start; gap:.5rem; }}
  .plugin-name {{ font-weight:700; font-size:.95rem; font-family:Consolas,monospace; }}
  .stars {{ font-size:.8rem; color:var(--yellow); white-space:nowrap; }}
  .marketplace {{ font-size:.72rem; color:var(--accent); margin:.2rem 0 .4rem; }}
  .desc {{ font-size:.82rem; color:var(--muted); line-height:1.55; }}
  .version-info {{ font-size:.75rem; color:var(--yellow); margin-top:.4rem; }}
  .cb {{ accent-color:var(--green); width:16px; height:16px; flex-shrink:0; margin-top:3px; }}
  .update-btn {{ background:var(--accent); color:#fff; border:none; border-radius:6px;
                 padding:4px 14px; font-size:.8rem; font-weight:600; cursor:pointer;
                 white-space:nowrap; }}
  .footer {{ margin-top:2.5rem; padding-top:1rem; border-top:1px solid var(--border);
             font-size:.78rem; color:var(--muted); }}
  .status {{ position:fixed; bottom:1.5rem; right:1.5rem; background:var(--surface2);
             border:1px solid var(--border); border-radius:8px; padding:.6rem 1rem;
             font-size:.8rem; display:none; }}
</style>
</head>
<body>
<div class="header">
  <div>
    <h1>⚡ Claude Plugin Digest</h1>
    <div class="meta">{date_str} &nbsp;·&nbsp; Top {count} uninstalled by GitHub stars</div>
  </div>
  <button class="install-btn" id="installBtn" disabled onclick="installSelected()">Install Selected (0)</button>
</div>
<div class="hint">
  <span>Check plugins you want, then click <strong>Install Selected</strong></span>
  <span id="count-label">0 selected</span>
</div>
<div class="grid">{top10_cards}</div>
{updates_section}
<div class="footer">
  Run <code>/crisp-dev:plugin-digest</code> to refresh &nbsp;·&nbsp; Next auto-refresh: tomorrow 9:00 AM
</div>
<div class="status" id="status"></div>
<script>
function toggle(card) {{
  const cb = card.querySelector('.cb');
  if (!cb) return;
  cb.checked = !cb.checked;
  card.classList.toggle('selected', cb.checked);
  updateCount();
}}
function updateCount() {{
  const n = document.querySelectorAll('.cb:checked').length;
  document.getElementById('count-label').textContent = n + ' selected';
  const btn = document.getElementById('installBtn');
  btn.textContent = 'Install Selected (' + n + ')';
  btn.disabled = n === 0;
}}
function showStatus(msg) {{
  const s = document.getElementById('status');
  s.textContent = msg; s.style.display = 'block';
  setTimeout(() => s.style.display = 'none', 4000);
}}
function installSelected() {{
  const repos = [...document.querySelectorAll('.cb:checked')].map(cb => cb.dataset.repo);
  repos.forEach(repo => {{
    fetch('http://localhost:{port}/install?repo=' + encodeURIComponent(repo))
      .then(r => r.json())
      .then(d => showStatus(d.message || 'Installing ' + repo))
      .catch(() => showStatus('Install triggered for ' + repo));
  }});
}}
function doUpdate(encodedRepo, btn) {{
  btn.disabled = true; btn.textContent = 'Updating...';
  fetch('http://localhost:{port}/install?repo=' + encodedRepo + '&update=1')
    .then(r => r.json())
    .then(d => {{ btn.textContent = 'Updated!'; showStatus(d.message || 'Updated'); }})
    .catch(() => {{ btn.textContent = 'Updated'; }});
}}
</script>
</body>
</html>"""


def main():
    use_cached = "--cached" in sys.argv
    print("Plugin Digest starting...")

if __name__ == "__main__":
    main()
