# Plugin Digest — Install Confirmation & Page Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a styled dark-theme confirmation modal before install and auto-refresh the page after install completes, removing newly-installed plugins from the list.

**Architecture:** Two changes to `fetch_and_generate.py`: (1) a `/refresh` endpoint added to `InstallHandler` that re-reads cache + installed state and regenerates HTML, (2) modal HTML/CSS/JS injected into `generate_html()` that gates install behind a confirm dialog and calls `/refresh` + `location.reload()` on completion.

**Tech Stack:** Python 3.11+, stdlib only (`http.server`, `json`, `threading`), pytest, browser-side vanilla JS

---

## File Map

| File | Change |
|------|--------|
| `skills/plugin-digest/scripts/fetch_and_generate.py` | Add `/refresh` handler, update `make_install_handler(port)` signature, add modal HTML/CSS/JS to `generate_html()`, rename `installSelected` → `openModal`, update button onclick |
| `skills/plugin-digest/tests/test_server.py` | New — tests for `/refresh` endpoint |
| `skills/plugin-digest/tests/test_html.py` | Add tests for modal markup and JS functions |

---

### Task 1: `/refresh` server endpoint

**Files:**
- Modify: `skills/plugin-digest/scripts/fetch_and_generate.py`
- Create: `skills/plugin-digest/tests/test_server.py`

The `/refresh` handler re-reads `DIGEST_CACHE`, filters against the current `installed_plugins.json`, regenerates HTML, and writes it to `DIGEST_HTML`. The `make_install_handler` factory needs to accept `port` so the handler can pass it to `generate_html()`.

- [ ] **Step 1: Write failing tests for `/refresh`**

Create `skills/plugin-digest/tests/test_server.py`:

```python
import sys, pathlib, json, threading
import http.client
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from unittest.mock import patch
import fetch_and_generate as fag
from fetch_and_generate import make_install_handler, find_free_port
import http.server


def _start_test_server(port: int) -> http.server.HTTPServer:
    handler = make_install_handler(port)
    server = http.server.HTTPServer(("localhost", port), handler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    return server


def test_refresh_returns_200_and_writes_html(tmp_path):
    cache_data = {
        "top10": [{"full_name": "a/my-plugin", "stargazers_count": 100, "description": "test"}],
        "needs_update": []
    }
    port = find_free_port()
    cache_file = tmp_path / "plugin-digest-cache.json"
    html_file = tmp_path / "plugin-digest.html"
    cache_file.write_text(json.dumps(cache_data))

    server = _start_test_server(port)
    try:
        with patch.object(fag, "DIGEST_CACHE", cache_file), \
             patch.object(fag, "DIGEST_HTML", html_file), \
             patch("fetch_and_generate.get_installed_plugins", return_value={}), \
             patch("fetch_and_generate.get_installed_repo_names", return_value=set()):
            conn = http.client.HTTPConnection("localhost", port, timeout=5)
            conn.request("GET", "/refresh")
            resp = conn.getresponse()
            body = json.loads(resp.read())
    finally:
        server.shutdown()

    assert resp.status == 200
    assert body["success"] is True
    assert html_file.exists()
    assert "my-plugin" in html_file.read_text()


def test_refresh_filters_newly_installed_plugin(tmp_path):
    cache_data = {
        "top10": [
            {"full_name": "a/my-plugin", "stargazers_count": 100, "description": "test"},
            {"full_name": "b/other-plugin", "stargazers_count": 50, "description": "other"},
        ],
        "needs_update": []
    }
    port = find_free_port()
    cache_file = tmp_path / "plugin-digest-cache.json"
    html_file = tmp_path / "plugin-digest.html"
    cache_file.write_text(json.dumps(cache_data))

    server = _start_test_server(port)
    try:
        with patch.object(fag, "DIGEST_CACHE", cache_file), \
             patch.object(fag, "DIGEST_HTML", html_file), \
             patch("fetch_and_generate.get_installed_plugins", return_value={}), \
             patch("fetch_and_generate.get_installed_repo_names", return_value={"a/my-plugin"}):
            conn = http.client.HTTPConnection("localhost", port, timeout=5)
            conn.request("GET", "/refresh")
            resp = conn.getresponse()
            resp.read()
    finally:
        server.shutdown()

    html_content = html_file.read_text()
    assert "my-plugin" not in html_content   # filtered — just installed
    assert "other-plugin" in html_content    # still uninstalled, still shows


def test_refresh_returns_500_when_no_cache(tmp_path):
    port = find_free_port()
    missing_cache = tmp_path / "nonexistent-cache.json"
    html_file = tmp_path / "plugin-digest.html"

    server = _start_test_server(port)
    try:
        with patch.object(fag, "DIGEST_CACHE", missing_cache), \
             patch.object(fag, "DIGEST_HTML", html_file):
            conn = http.client.HTTPConnection("localhost", port, timeout=5)
            conn.request("GET", "/refresh")
            resp = conn.getresponse()
            body = json.loads(resp.read())
    finally:
        server.shutdown()

    assert resp.status == 500
    assert body["success"] is False
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd "C:/Users/bseay/source/repos/SkillsOfTheKraken/skills/plugin-digest"
pytest tests/test_server.py -v
```

Expected: `ImportError` or `AttributeError` — `make_install_handler` doesn't accept `port` yet, `/refresh` not implemented.

- [ ] **Step 3: Update `make_install_handler` to accept `port` and add `/refresh` handler**

In `fetch_and_generate.py`, change `make_install_handler()` to `make_install_handler(port: int)` and add the `/refresh` path. Full updated function:

```python
def make_install_handler(port: int):
    """Return a request handler class with access to run_install and port."""

    class InstallHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            params = urllib.parse.parse_qs(parsed.query)

            if parsed.path == "/install":
                repo = params.get("repo", [""])[0]
                if repo:
                    result_container = {}
                    def do_install():
                        result_container["result"] = run_install(repo)
                    t = threading.Thread(target=do_install)
                    t.start()
                    t.join(timeout=5)

                    result = result_container.get("result",
                        {"success": True, "message": f"Installing {repo} in background..."})
                    self._respond(200, result)
                else:
                    self._respond(400, {"success": False, "message": "Missing repo parameter"})

            elif parsed.path == "/refresh":
                try:
                    cache = json.loads(DIGEST_CACHE.read_text(encoding="utf-8"))
                    top10_raw = cache.get("top10", [])
                    needs_update = cache.get("needs_update", [])
                    installed = get_installed_plugins()
                    installed_repo_names = get_installed_repo_names(installed)
                    top10 = filter_uninstalled(top10_raw, installed_repo_names)[:10]
                    html_content = generate_html(top10, needs_update, port)
                    DIGEST_HTML.parent.mkdir(parents=True, exist_ok=True)
                    DIGEST_HTML.write_text(html_content, encoding="utf-8")
                    self._respond(200, {"success": True})
                except Exception as e:
                    self._respond(500, {"success": False, "message": str(e)})

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
            pass

    return InstallHandler
```

- [ ] **Step 4: Update `start_install_server` to pass `port` to `make_install_handler`**

```python
def start_install_server() -> tuple[int, http.server.HTTPServer]:
    """Start the local install server, return (port, server)."""
    port = find_free_port()
    handler = make_install_handler(port)
    server = http.server.HTTPServer(("localhost", port), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return port, server
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
pytest tests/test_server.py -v
```

Expected:
```
tests/test_server.py::test_refresh_returns_200_and_writes_html PASSED
tests/test_server.py::test_refresh_filters_newly_installed_plugin PASSED
tests/test_server.py::test_refresh_returns_500_when_no_cache PASSED
```

- [ ] **Step 6: Run full test suite — no regressions**

```bash
pytest tests/ -v
```

Expected: all existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add skills/plugin-digest/scripts/fetch_and_generate.py skills/plugin-digest/tests/test_server.py
git commit -m "feat: add /refresh endpoint to plugin-digest server"
```

---

### Task 2: Confirmation modal HTML/CSS/JS

**Files:**
- Modify: `skills/plugin-digest/scripts/fetch_and_generate.py`
- Modify: `skills/plugin-digest/tests/test_html.py`

Add a dark-theme modal overlay that gates install behind a confirm dialog. Replace the `installSelected()` JS function with `openModal()`. Add `closeModal()`, `confirmInstall()`, and `refreshPage()`. Update the install button's `onclick`.

- [ ] **Step 1: Write failing tests for modal**

Add to the bottom of `skills/plugin-digest/tests/test_html.py`:

```python
def test_modal_overlay_present():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert 'id="modal-overlay"' in html

def test_install_button_calls_open_modal():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert 'onclick="openModal()"' in html

def test_modal_js_functions_present():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "function openModal()" in html
    assert "function closeModal()" in html
    assert "function confirmInstall()" in html
    assert "function refreshPage()" in html

def test_refresh_url_in_js():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "localhost:9999/refresh" in html

def test_install_selected_function_removed():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "function installSelected()" not in html
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_html.py -v -k "modal or open_modal or refresh_url or install_selected"
```

Expected: 5 failures — modal markup and functions not present yet.

- [ ] **Step 3: Add modal CSS to `generate_html()`**

Inside `generate_html()`, find the `<style>` block in the returned f-string. After the existing `.status` rule (last CSS rule before `</style>`), add:

```python
  .modal-overlay {{ position:fixed; inset:0; background:rgba(0,0,0,.6);
                    display:flex; align-items:center; justify-content:center; z-index:100; }}
  .modal {{ background:var(--surface2); border:1px solid var(--border); border-radius:12px;
            padding:1.5rem; min-width:320px; max-width:480px; }}
  .modal-title {{ font-weight:700; font-size:1rem; margin-bottom:1rem; }}
  .modal-list {{ list-style:none; margin-bottom:1.25rem; display:flex; flex-direction:column; gap:.4rem; }}
  .modal-list li {{ font-family:Consolas,monospace; font-size:.85rem; color:var(--accent); }}
  .modal-actions {{ display:flex; gap:.75rem; justify-content:flex-end; }}
  .modal-cancel {{ background:transparent; border:1px solid var(--border); color:var(--muted);
                   border-radius:6px; padding:7px 16px; cursor:pointer; font-size:.85rem; }}
  .modal-cancel:hover {{ border-color:var(--text); color:var(--text); }}
  .modal-confirm {{ background:var(--green); color:#fff; border:none; border-radius:6px;
                    padding:7px 16px; cursor:pointer; font-size:.85rem; font-weight:600; }}
  .modal-confirm:disabled {{ background:var(--border); color:var(--muted); cursor:default; }}
```

- [ ] **Step 4: Add modal HTML markup to `generate_html()`**

Inside the f-string body, just before `<div class="status" id="status"></div>`, add:

```python
<div id="modal-overlay" class="modal-overlay" style="display:none">
  <div class="modal">
    <div class="modal-title">Install plugins?</div>
    <ul id="modal-list" class="modal-list"></ul>
    <div class="modal-actions">
      <button class="modal-cancel" id="modal-cancel-btn" onclick="closeModal()">Cancel</button>
      <button class="modal-confirm" id="modal-confirm-btn" onclick="confirmInstall()">
        Install <span id="modal-count"></span> plugins
      </button>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Replace `installSelected()` JS with modal functions**

In the `<script>` block of `generate_html()`, replace:

```python
function installSelected() {{
  const repos = [...document.querySelectorAll('.cb:checked')].map(cb => cb.dataset.repo);
  repos.forEach(repo => {{
    fetch('http://localhost:{port}/install?repo=' + encodeURIComponent(repo))
      .then(r => r.json())
      .then(d => showStatus(d.message || 'Installing ' + repo))
      .catch(() => showStatus('Install triggered for ' + repo));
  }});
}}
```

With:

```python
let _pendingRepos = [];
function openModal() {{
  _pendingRepos = [...document.querySelectorAll('.cb:checked')].map(cb => cb.dataset.repo);
  if (!_pendingRepos.length) return;
  const list = document.getElementById('modal-list');
  list.innerHTML = _pendingRepos.map(r => '<li>' + r.split('/').pop() + '</li>').join('');
  document.getElementById('modal-count').textContent = _pendingRepos.length;
  document.getElementById('modal-overlay').style.display = 'flex';
}}
function closeModal() {{
  document.getElementById('modal-overlay').style.display = 'none';
}}
function confirmInstall() {{
  const confirmBtn = document.getElementById('modal-confirm-btn');
  const cancelBtn = document.getElementById('modal-cancel-btn');
  confirmBtn.disabled = true;
  confirmBtn.textContent = 'Installing...';
  cancelBtn.disabled = true;
  Promise.all(_pendingRepos.map(repo =>
    fetch('http://localhost:{port}/install?repo=' + encodeURIComponent(repo))
      .then(r => r.json())
      .catch(() => ({{ success: false, message: 'Network error' }}))
  )).then(() => {{
    closeModal();
    refreshPage();
  }});
}}
function refreshPage() {{
  fetch('http://localhost:{port}/refresh')
    .then(() => location.reload())
    .catch(() => location.reload());
}}
```

- [ ] **Step 6: Update install button `onclick` in `generate_html()`**

Find:
```python
  <button class="install-btn" id="installBtn" disabled onclick="installSelected()">Install Selected (0)</button>
```

Change to:
```python
  <button class="install-btn" id="installBtn" disabled onclick="openModal()">Install Selected (0)</button>
```

- [ ] **Step 7: Run new modal tests**

```bash
pytest tests/test_html.py -v -k "modal or open_modal or refresh_url or install_selected"
```

Expected: all 5 pass.

- [ ] **Step 8: Run full test suite**

```bash
pytest tests/ -v
```

Expected: all tests pass. The existing `test_install_buttons_point_to_local_server` still passes because `confirmInstall()` still calls `/install`.

- [ ] **Step 9: Commit**

```bash
git add skills/plugin-digest/scripts/fetch_and_generate.py skills/plugin-digest/tests/test_html.py
git commit -m "feat: add install confirmation modal and page refresh to plugin-digest"
```

---

### Task 3: Push and sync cache

**Files:**
- `addclaudeskills.ps1` (re-run to pull updated skill into cache)

After both code tasks pass, push to GitHub and update the local plugin cache so the live skill picks up the changes.

- [ ] **Step 1: Push to GitHub**

```bash
git push
```

- [ ] **Step 2: Re-run installer to sync cache**

```powershell
powershell -ExecutionPolicy Bypass -File .\addclaudeskills.ps1
```

Expected: downloads latest repo, repopulates `~\.claude\plugins\cache\SkillsOfTheKraken\crisp-dev\1.0.0\skills\plugin-digest\`.

- [ ] **Step 3: Verify live skill has modal**

```powershell
Select-String -Path "$env:USERPROFILE\.claude\plugins\cache\SkillsOfTheKraken\crisp-dev\1.0.0\skills\plugin-digest\scripts\fetch_and_generate.py" -Pattern "openModal"
```

Expected: matches found.

---

## Self-Review

**Spec coverage:**
- ✅ Styled confirmation modal with Cancel / Install N plugins buttons → Task 2
- ✅ Buttons disabled + "Installing..." during install → Task 2 Step 5
- ✅ `/refresh` endpoint regenerates HTML from cache → Task 1
- ✅ `PORT` accessible inside handler via closure → Task 1 Step 3 (`make_install_handler(port)`)
- ✅ `refreshPage()` reloads even on error → Task 2 Step 5 (`.catch(() => location.reload())`)
- ✅ `doUpdate` unchanged → not touched anywhere in plan
- ✅ No new GitHub API calls on refresh → Task 1 Step 3 (uses `DIGEST_CACHE`, not GitHub)

**Placeholder scan:** None found. All code blocks complete.

**Type consistency:** `make_install_handler(port: int)` defined in Task 1 Step 3, called in Task 1 Step 4. `openModal`/`closeModal`/`confirmInstall`/`refreshPage` all defined and referenced consistently in Task 2.
