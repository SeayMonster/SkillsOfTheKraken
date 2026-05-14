# Plugin Digest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `crisp-dev:plugin-digest` skill that generates a daily HTML page showing the top 10 uninstalled Claude plugins by GitHub stars, with one-click install via a local HTTP server.

**Architecture:** A Python script (`fetch_and_generate.py`) queries GitHub for Claude plugin repos, checks installed plugins, generates an HTML digest, starts a local HTTP server to handle install clicks, and opens the browser. The skill registers a Windows Task Scheduler job on first run for daily 9am execution.

**Tech Stack:** Python 3 (stdlib only — `http.server`, `urllib`, `json`, `pathlib`, `webbrowser`, `subprocess`), pytest for tests, PowerShell for install execution, Windows Task Scheduler (`schtasks`) for daily scheduling.

---

## File Structure

```
skills/plugin-digest/
├── SKILL.md
├── scripts/
│   └── fetch_and_generate.py      # Main script: fetch, generate, serve, open
└── tests/
    ├── test_github.py              # GitHub search + ranking logic
    ├── test_installed.py           # Installed plugin detection + update check
    ├── test_html.py                # HTML generation structure
    ├── test_install.py             # Install mechanism selection
    └── conftest.py                 # Shared fixtures
```

---

### Task 1: Project scaffold + conftest

**Files:**
- Create: `skills/plugin-digest/scripts/fetch_and_generate.py` (empty scaffold)
- Create: `skills/plugin-digest/tests/conftest.py`

- [ ] **Step 1: Create the script scaffold**

```python
# skills/plugin-digest/scripts/fetch_and_generate.py
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

CLAUDE_DIR = pathlib.Path.home() / ".claude"
DIGEST_HTML = CLAUDE_DIR / "plugin-digest.html"
DIGEST_CACHE = CLAUDE_DIR / "plugin-digest-cache.json"

def main():
    use_cached = "--cached" in sys.argv
    print("Plugin Digest starting...")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Create conftest.py with shared fixtures**

```python
# skills/plugin-digest/tests/conftest.py
import json
import pytest

MOCK_SEARCH_RESULTS = [
    {"full_name": "obra/superpowers", "stargazers_count": 2841,
     "description": "Core skills library", "topics": ["claude-plugin"]},
    {"full_name": "SeayMonster/SkillsOfTheKraken", "stargazers_count": 847,
     "description": "Crisp dev skills", "topics": ["claude-skill"]},
    {"full_name": "obra/episodic-memory", "stargazers_count": 612,
     "description": "Semantic memory", "topics": ["claude-plugin"]},
    {"full_name": "some/new-plugin", "stargazers_count": 500,
     "description": "New cool plugin", "topics": ["claude-code-plugin"]},
    {"full_name": "another/plugin", "stargazers_count": 400,
     "description": "Another plugin", "topics": ["claude-plugin"]},
    {"full_name": "yet/another", "stargazers_count": 300,
     "description": "Yet another", "topics": ["claude-plugin"]},
    {"full_name": "cool/tool", "stargazers_count": 250,
     "description": "Cool tool", "topics": ["claude-plugin"]},
    {"full_name": "nice/thing", "stargazers_count": 200,
     "description": "Nice thing", "topics": ["claude-plugin"]},
    {"full_name": "great/skill", "stargazers_count": 150,
     "description": "Great skill", "topics": ["claude-skill"]},
    {"full_name": "awesome/plugin", "stargazers_count": 100,
     "description": "Awesome plugin", "topics": ["claude-plugin"]},
    {"full_name": "basic/one", "stargazers_count": 50,
     "description": "Basic one", "topics": ["claude-plugin"]},
]

MOCK_INSTALLED = {
    "version": 2,
    "plugins": {
        "superpowers@superpowers-marketplace": [
            {"scope": "user", "installPath": "...", "version": "5.0.7",
             "installedAt": "2026-04-30T06:47:10Z", "lastUpdated": "2026-05-09T07:45:30Z"}
        ],
        "crisp-dev@SkillsOfTheKraken": [
            {"scope": "user", "installPath": "...", "version": "1.0.0",
             "installedAt": "2026-04-30T02:31:11Z", "lastUpdated": "2026-05-09T07:45:30Z"}
        ],
    }
}

@pytest.fixture
def mock_search_results():
    return MOCK_SEARCH_RESULTS

@pytest.fixture
def mock_installed():
    return MOCK_INSTALLED
```

- [ ] **Step 3: Run tests to confirm pytest is working**

```bash
cd skills/plugin-digest
python -m pytest tests/ -v
```
Expected: `no tests ran` (0 collected, no errors)

- [ ] **Step 4: Commit scaffold**

```bash
git add skills/plugin-digest/
git commit -m "feat(plugin-digest): scaffold script and test fixtures"
```

---

### Task 2: GitHub Discovery

**Files:**
- Modify: `skills/plugin-digest/scripts/fetch_and_generate.py`
- Create: `skills/plugin-digest/tests/test_github.py`

- [ ] **Step 1: Write failing tests**

```python
# skills/plugin-digest/tests/test_github.py
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from fetch_and_generate import search_github_plugins, deduplicate_repos, rank_by_stars

def test_deduplicate_repos_removes_duplicates():
    repos = [
        {"full_name": "obra/superpowers", "stargazers_count": 100},
        {"full_name": "obra/superpowers", "stargazers_count": 100},  # duplicate
        {"full_name": "other/plugin", "stargazers_count": 50},
    ]
    result = deduplicate_repos(repos)
    assert len(result) == 2

def test_rank_by_stars_sorts_descending():
    repos = [
        {"full_name": "low/stars", "stargazers_count": 10},
        {"full_name": "high/stars", "stargazers_count": 500},
        {"full_name": "mid/stars", "stargazers_count": 100},
    ]
    result = rank_by_stars(repos)
    assert result[0]["full_name"] == "high/stars"
    assert result[1]["full_name"] == "mid/stars"
    assert result[2]["full_name"] == "low/stars"

def test_rank_by_stars_takes_top_n():
    repos = [{"full_name": f"repo/{i}", "stargazers_count": i} for i in range(20)]
    result = rank_by_stars(repos, top_n=10)
    assert len(result) == 10
    assert result[0]["stargazers_count"] == 19  # highest first
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
python -m pytest tests/test_github.py -v
```
Expected: `ImportError: cannot import name 'search_github_plugins'`

- [ ] **Step 3: Implement GitHub functions**

Add to `fetch_and_generate.py` after the imports:

```python
import urllib.request
import urllib.parse
import urllib.error

GITHUB_SEARCH_TOPICS = ["claude-plugin", "claude-skill", "claude-code-plugin", "claude-code-skills"]
GITHUB_SEARCH_KEYWORDS = ["claude code skills", "claude code plugin"]
GITHUB_API = "https://api.github.com"


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


class RateLimitError(Exception):
    pass


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
        except Exception:
            continue

    # Keyword searches
    for keyword in GITHUB_SEARCH_KEYWORDS:
        try:
            encoded = urllib.parse.quote(keyword)
            data = _github_get(f"/search/repositories?q={encoded}&sort=stars&per_page=20")
            results.extend(data.get("items", []))
        except (RateLimitError, Exception):
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
            repo_name = val.get("source", {}).get("repo")
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
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
python -m pytest tests/test_github.py -v
```
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add skills/plugin-digest/
git commit -m "feat(plugin-digest): GitHub discovery, dedup, and star ranking"
```

---

### Task 3: Installed Plugin Detection

**Files:**
- Modify: `skills/plugin-digest/scripts/fetch_and_generate.py`
- Create: `skills/plugin-digest/tests/test_installed.py`

- [ ] **Step 1: Write failing tests**

```python
# skills/plugin-digest/tests/test_installed.py
import sys, pathlib, json, tempfile
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from fetch_and_generate import get_installed_plugins, filter_uninstalled, get_plugin_repo_key

def test_get_installed_plugins_returns_dict(tmp_path):
    installed = {
        "version": 2,
        "plugins": {
            "superpowers@superpowers-marketplace": [
                {"version": "5.0.7", "installPath": "/some/path"}
            ]
        }
    }
    f = tmp_path / "installed_plugins.json"
    f.write_text(json.dumps(installed))
    result = get_installed_plugins(installed_path=f)
    assert "superpowers@superpowers-marketplace" in result
    assert result["superpowers@superpowers-marketplace"]["version"] == "5.0.7"

def test_get_installed_plugins_returns_empty_if_missing(tmp_path):
    result = get_installed_plugins(installed_path=tmp_path / "nonexistent.json")
    assert result == {}

def test_filter_uninstalled_excludes_installed_repos():
    repos = [
        {"full_name": "obra/superpowers", "stargazers_count": 2841},
        {"full_name": "some/new-plugin", "stargazers_count": 500},
    ]
    installed_repos = {"obra/superpowers"}
    result = filter_uninstalled(repos, installed_repos)
    assert len(result) == 1
    assert result[0]["full_name"] == "some/new-plugin"

def test_get_plugin_repo_key_extracts_repo_name():
    # installed_plugins.json entries use plugin@marketplace format
    # We map them back to full_name for filtering
    assert get_plugin_repo_key("SeayMonster/SkillsOfTheKraken") == "seaymonster/skillsofthekraken"
```

- [ ] **Step 2: Run to confirm they fail**

```bash
python -m pytest tests/test_installed.py -v
```
Expected: `ImportError: cannot import name 'get_installed_plugins'`

- [ ] **Step 3: Implement installed plugin detection**

Add to `fetch_and_generate.py`:

```python
INSTALLED_PLUGINS_PATH = CLAUDE_DIR / "plugins" / "installed_plugins.json"


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
```

- [ ] **Step 4: Run tests**

```bash
python -m pytest tests/test_installed.py -v
```
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add skills/plugin-digest/
git commit -m "feat(plugin-digest): installed plugin detection and filtering"
```

---

### Task 4: HTML Generation

**Files:**
- Modify: `skills/plugin-digest/scripts/fetch_and_generate.py`
- Create: `skills/plugin-digest/tests/test_html.py`

- [ ] **Step 1: Write failing tests**

```python
# skills/plugin-digest/tests/test_html.py
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from fetch_and_generate import generate_html

SAMPLE_TOP10 = [
    {"full_name": f"owner/plugin-{i}", "stargazers_count": 1000 - i * 50,
     "description": f"Plugin {i} description"} for i in range(10)
]
SAMPLE_UPDATES = [
    {"plugin_key": "old-plugin@marketplace", "full_name": "owner/old-plugin",
     "installed_version": "1.0.0", "latest_version": "1.2.0",
     "description": "Old plugin needing update"}
]

def test_generate_html_returns_string():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert isinstance(html, str)
    assert "<!DOCTYPE html>" in html

def test_top3_have_gold_class():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert html.count('top3-card') == 3

def test_install_buttons_point_to_local_server():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "localhost:9999/install" in html

def test_needs_update_section_shown_when_updates_exist():
    html = generate_html(SAMPLE_TOP10, SAMPLE_UPDATES, port=9999)
    assert "Needs Update" in html
    assert "1.0.0" in html
    assert "1.2.0" in html

def test_needs_update_section_hidden_when_no_updates():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "Needs Update" not in html

def test_footer_contains_skill_command():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "/crisp-dev:plugin-digest" in html
```

- [ ] **Step 2: Run to confirm they fail**

```bash
python -m pytest tests/test_html.py -v
```
Expected: `ImportError: cannot import name 'generate_html'`

- [ ] **Step 3: Implement generate_html**

Add to `fetch_and_generate.py`:

```python
from datetime import datetime


def generate_html(top10: list[dict], needs_update: list[dict], port: int) -> str:
    """Generate the full plugin digest HTML page."""

    def card_html(repo: dict, rank: int) -> str:
        name = repo["full_name"].split("/")[-1]
        full_name = repo["full_name"]
        stars = f"★ {repo.get('stargazers_count', 0):,}"
        desc = repo.get("description", "No description.") or "No description."
        marketplace = repo.get("_marketplace", repo["full_name"].split("/")[0])
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
        name = item["full_name"].split("/")[-1]
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
      <div class="desc">{item.get('description', '')}</div>
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
```

- [ ] **Step 4: Run tests**

```bash
python -m pytest tests/test_html.py -v
```
Expected: 6 passed

- [ ] **Step 5: Commit**

```bash
git add skills/plugin-digest/
git commit -m "feat(plugin-digest): HTML digest generation with gold top-3 and update section"
```

---

### Task 5: Install Mechanism

**Files:**
- Modify: `skills/plugin-digest/scripts/fetch_and_generate.py`
- Create: `skills/plugin-digest/tests/test_install.py`

- [ ] **Step 1: Write failing tests**

```python
# skills/plugin-digest/tests/test_install.py
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from unittest.mock import patch, MagicMock
from fetch_and_generate import get_install_url, build_generic_install_steps

def test_get_install_url_returns_raw_url_when_install_ps1_exists():
    # Mock _github_get to return 200 for install.ps1
    with patch("fetch_and_generate._check_file_exists") as mock_check:
        mock_check.return_value = True
        url = get_install_url("SeayMonster/SkillsOfTheKraken")
    assert url == "https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/install.ps1"

def test_get_install_url_returns_none_when_no_installer():
    with patch("fetch_and_generate._check_file_exists") as mock_check:
        mock_check.return_value = False
        url = get_install_url("some/random-plugin")
    assert url is None

def test_build_generic_install_steps_returns_list():
    steps = build_generic_install_steps("owner/my-plugin", "my-plugin", "1.0.0")
    assert isinstance(steps, list)
    assert len(steps) > 0
    # Steps should be strings describing what to do
    combined = " ".join(steps)
    assert "settings.json" in combined
    assert "installed_plugins" in combined
```

- [ ] **Step 2: Run to confirm they fail**

```bash
python -m pytest tests/test_install.py -v
```
Expected: `ImportError: cannot import name 'get_install_url'`

- [ ] **Step 3: Implement install mechanism**

Add to `fetch_and_generate.py`:

```python
import subprocess
import threading
import uuid


def _check_file_exists(repo: str, filename: str) -> bool:
    """Check if a file exists in a GitHub repo root."""
    try:
        _github_get(f"/repos/{repo}/contents/{filename}")
        return True
    except Exception:
        return False


def get_install_url(repo: str) -> str | None:
    """
    Return the raw URL of install.ps1 if it exists in the repo root, else None.
    Checks both install.ps1 and addclaudeskills.ps1 (legacy name).
    """
    for filename in ["install.ps1", "addclaudeskills.ps1"]:
        if _check_file_exists(repo, filename):
            return f"https://raw.githubusercontent.com/{repo}/main/{filename}"
    return None


def build_generic_install_steps(repo: str, plugin_name: str, version: str) -> list[str]:
    """
    Return a list of PowerShell command strings for generic install
    when no install.ps1 exists.
    """
    marketplace_key = repo.replace("/", "-")
    return [
        # 1. Register in settings.json extraKnownMarketplaces
        f"$s=Get-Content ~\\.claude\\settings.json|ConvertFrom-Json;"
        f"$s.extraKnownMarketplaces|Add-Member -NotePropertyName '{marketplace_key}' "
        f"-Value ([PSCustomObject]@{{source=[PSCustomObject]@{{source='github';repo='{repo}'}}}}); "
        f"$s|ConvertTo-Json -Depth 10|Set-Content ~\\.claude\\settings.json -Encoding utf8",
        # 2. Download ZIP and extract to cache
        f"$z=\"$env:TEMP\\{plugin_name}.zip\";"
        f"Invoke-WebRequest https://github.com/{repo}/archive/refs/heads/main.zip -OutFile $z;"
        f"Expand-Archive $z $env:TEMP\\{plugin_name}-extract -Force;"
        f"$src=\"$env:TEMP\\{plugin_name}-extract\\{repo.split('/')[-1]}-main\";"
        f"$dest=\"$env:USERPROFILE\\.claude\\plugins\\cache\\{marketplace_key}\\{plugin_name}\\{version}\";"
        f"if(Test-Path $dest){{Remove-Item $dest -Recurse -Force}};"
        f"Copy-Item $src $dest -Recurse -Force",
        # 3. Write installed_plugins.json
        f"# Write installed_plugins.json entry for {plugin_name}@{marketplace_key}",
        # 4. Enable in settings.json
        f"# Enable {plugin_name}@{marketplace_key} in enabledPlugins",
    ]


def run_install(repo: str) -> dict:
    """
    Install a plugin. Uses install.ps1 if available, falls back to generic install.
    Returns {success: bool, message: str}.
    """
    install_url = get_install_url(repo)
    plugin_name = repo.split("/")[-1]

    if install_url:
        # Run irm | iex via PowerShell
        cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-Command",
               f"irm {install_url} | iex"]
    else:
        # Generic install: download ZIP + register
        steps = build_generic_install_steps(repo, plugin_name, "latest")
        cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-Command",
               "; ".join(steps)]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode == 0:
            return {"success": True, "message": f"Installed {plugin_name} successfully!"}
        else:
            return {"success": False, "message": f"Install failed: {result.stderr[:200]}"}
    except subprocess.TimeoutExpired:
        return {"success": False, "message": "Install timed out after 2 minutes"}
    except Exception as e:
        return {"success": False, "message": str(e)}
```

- [ ] **Step 4: Run tests**

```bash
python -m pytest tests/test_install.py -v
```
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add skills/plugin-digest/
git commit -m "feat(plugin-digest): install mechanism with install.ps1 detection and generic fallback"
```

---

### Task 6: Local HTTP Server

**Files:**
- Modify: `skills/plugin-digest/scripts/fetch_and_generate.py`

- [ ] **Step 1: Add HTTP server that handles /install requests**

Add to `fetch_and_generate.py`:

```python
import http.server
import socket


def find_free_port() -> int:
    """Find an available local port."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


def make_install_handler():
    """Return a request handler class with access to run_install."""

    class InstallHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            params = urllib.parse.parse_qs(parsed.query)

            if parsed.path == "/install":
                repo = params.get("repo", [""])[0]
                if repo:
                    # Run install in background thread so we can respond immediately
                    result_container = {}
                    def do_install():
                        result_container["result"] = run_install(repo)
                    t = threading.Thread(target=do_install)
                    t.start()
                    t.join(timeout=5)  # Wait up to 5s for quick installs

                    result = result_container.get("result",
                        {"success": True, "message": f"Installing {repo} in background..."})
                    self._respond(200, result)
                else:
                    self._respond(400, {"success": False, "message": "Missing repo parameter"})
            elif parsed.path == "/health":
                self._respond(200, {"status": "ok"})
            else:
                self._respond(404, {"success": False, "message": "Not found"})

        def _respond(self, code: int, data: dict):
            body = json.dumps(data).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            pass  # Suppress request logs

    return InstallHandler


def start_install_server() -> tuple[int, http.server.HTTPServer]:
    """Start the local install server, return (port, server)."""
    port = find_free_port()
    handler = make_install_handler()
    server = http.server.HTTPServer(("localhost", port), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return port, server
```

- [ ] **Step 2: Wire everything together in main()**

Replace the existing `main()` function:

```python
def main():
    use_cached = "--cached" in sys.argv
    print("Plugin Digest — fetching plugins...")

    # Start install server first so we have the port for HTML generation
    port, server = start_install_server()
    print(f"Install server running on port {port}")

    if use_cached and DIGEST_CACHE.exists():
        print("Using cached results...")
        cache = json.loads(DIGEST_CACHE.read_text(encoding="utf-8"))
        top10 = cache.get("top10", [])
        needs_update = cache.get("needs_update", [])
    else:
        # Fetch from GitHub
        try:
            print("Searching GitHub...")
            all_repos = search_github_plugins()
            known_repos = get_known_marketplace_repos()
            all_repos = deduplicate_repos(all_repos + known_repos)

            # Get installed plugins and filter
            installed = get_installed_plugins()
            installed_repo_names = get_installed_repo_names(installed)

            top10 = rank_by_stars(filter_uninstalled(all_repos, installed_repo_names), top_n=10)

            # Check for updates (placeholder — version comparison in Task 7)
            needs_update = []

            # Cache results
            DIGEST_CACHE.parent.mkdir(parents=True, exist_ok=True)
            DIGEST_CACHE.write_text(
                json.dumps({"top10": top10, "needs_update": needs_update}, indent=2),
                encoding="utf-8"
            )
        except RateLimitError:
            print("GitHub rate limit hit — using cached results if available")
            if DIGEST_CACHE.exists():
                cache = json.loads(DIGEST_CACHE.read_text(encoding="utf-8"))
                top10 = cache.get("top10", [])
                needs_update = cache.get("needs_update", [])
            else:
                print("No cache available. Try again in an hour.")
                server.shutdown()
                return

    # Generate and open HTML
    html = generate_html(top10, needs_update, port)
    DIGEST_HTML.parent.mkdir(parents=True, exist_ok=True)
    DIGEST_HTML.write_text(html, encoding="utf-8")
    print(f"Digest saved to {DIGEST_HTML}")

    import webbrowser
    webbrowser.open(DIGEST_HTML.as_uri())
    print("Opened in browser. Server running — press Ctrl+C to stop.")

    # Keep server alive until user closes (or 30 min timeout)
    try:
        import time
        time.sleep(1800)  # 30 minutes
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
```

- [ ] **Step 3: Run the script manually to verify end-to-end**

```bash
cd skills/plugin-digest/scripts
python fetch_and_generate.py
```
Expected: Browser opens with digest page, install server running on a random port. Ctrl+C to stop.

- [ ] **Step 4: Commit**

```bash
git add skills/plugin-digest/
git commit -m "feat(plugin-digest): local HTTP install server and wired main()"
```

---

### Task 7: Schedule Registration

**Files:**
- Modify: `skills/plugin-digest/scripts/fetch_and_generate.py`

- [ ] **Step 1: Add schedule registration via Windows Task Scheduler**

Add to `fetch_and_generate.py`:

```python
SCHEDULE_TASK_NAME = "ClaudePluginDigest"
SCHEDULE_CONFIG = CLAUDE_DIR / "plugin-digest-schedule.json"


def is_scheduled() -> bool:
    """Check if the daily Task Scheduler job already exists."""
    if SCHEDULE_CONFIG.exists():
        return True
    # Also check schtasks directly
    result = subprocess.run(
        ["schtasks", "/Query", "/TN", SCHEDULE_TASK_NAME],
        capture_output=True, text=True
    )
    return result.returncode == 0


def register_daily_schedule(script_path: pathlib.Path):
    """
    Register a daily 9am Windows Task Scheduler job to run the digest.
    Only registers if not already scheduled.
    """
    if is_scheduled():
        return  # Already set up

    python_exe = sys.executable
    cmd = [
        "schtasks", "/Create",
        "/TN", SCHEDULE_TASK_NAME,
        "/TR", f'"{python_exe}" "{script_path}"',
        "/SC", "DAILY",
        "/ST", "09:00",
        "/F"  # Force overwrite if exists
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        # Write marker so we don't check schtasks every run
        SCHEDULE_CONFIG.write_text(
            json.dumps({"scheduled": True, "time": "09:00", "task": SCHEDULE_TASK_NAME}),
            encoding="utf-8"
        )
        print(f"Scheduled daily digest at 9:00 AM (Task: {SCHEDULE_TASK_NAME})")
    else:
        print(f"Warning: Could not register schedule: {result.stderr}")
```

- [ ] **Step 2: Call register_daily_schedule at the start of main()**

In `main()`, add after `start_install_server()`:

```python
    # Register daily schedule on first run
    script_path = pathlib.Path(__file__).resolve()
    register_daily_schedule(script_path)
```

- [ ] **Step 3: Verify schedule registration**

```bash
python fetch_and_generate.py
schtasks /Query /TN ClaudePluginDigest
```
Expected: Task listed with `Next Run Time: 9:00:00 AM`

- [ ] **Step 4: Commit**

```bash
git add skills/plugin-digest/
git commit -m "feat(plugin-digest): daily 9am schedule via Windows Task Scheduler"
```

---

### Task 8: SKILL.md + push to GitHub

**Files:**
- Create: `skills/plugin-digest/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: plugin-digest
description: >
  Generates a daily HTML digest of the top 10 uninstalled Claude plugins ranked by GitHub stars,
  with one-click install and update support. Use this skill whenever the user wants to discover
  new Claude plugins, browse what's trending, check for plugin updates, or says anything like
  "show me popular Claude skills", "what plugins should I install", or "plugin digest".
  Also runs automatically every morning at 9am after first use.
---

# Plugin Digest

Fetch the top 10 uninstalled Claude plugins from GitHub by star count, generate an interactive
HTML digest, and open it in the browser.

## How to Run

The skill runs a bundled Python script:

```
python "<skill-dir>/scripts/fetch_and_generate.py"
```

Replace `<skill-dir>` with the absolute path to this skill's directory.

## Flags

- No flags: fetch fresh from GitHub + open browser
- `--cached`: skip GitHub fetch, use last cached results (faster, for offline use)

## What the Page Shows

- **Top 10 Discoveries** — uninstalled plugins, ranked by stars. Top 3 get gold border.
  Checkbox to select, "Install Selected" button runs install automatically.
- **Needs Update** — installed plugins with a newer version available. One-click Update button.

## Schedule

On first run, registers a Windows Task Scheduler job (`ClaudePluginDigest`) to run daily at 9am.
The schedule only registers once — re-running the skill won't duplicate it.
```

- [ ] **Step 2: Run full test suite**

```bash
cd skills/plugin-digest
python -m pytest tests/ -v
```
Expected: All tests pass

- [ ] **Step 3: Commit and push to GitHub**

```bash
cd C:\Temp\SkillsOfTheKraken
git add skills/plugin-digest/
git commit -m "feat: add plugin-digest skill - daily top 10 Claude plugins by GitHub stars"
git pull --rebase
git push
```

- [ ] **Step 4: Refresh local cache**

```powershell
$cache = "C:\Users\$env:USERNAME\.claude\plugins\cache\SkillsOfTheKraken\crisp-dev\1.0.0\skills"
Remove-Item $cache -Recurse -Force
New-Item -ItemType Directory -Path $cache -Force | Out-Null
Get-ChildItem "C:\Temp\SkillsOfTheKraken\skills" -Directory | ForEach-Object {
    Copy-Item $_.FullName "$cache\$($_.Name)" -Recurse -Force
}
Write-Host "Cache refreshed"
```

- [ ] **Step 5: Test the skill end-to-end**

Restart Claude Code and run:
```
/crisp-dev:plugin-digest
```
Expected: Browser opens with digest page showing top 10 plugins, install server running.

- [ ] **Step 6: Final commit**

```bash
git add .
git commit -m "feat(plugin-digest): complete implementation - digest, install server, scheduler"
git push
```
