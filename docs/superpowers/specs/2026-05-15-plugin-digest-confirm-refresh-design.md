# Plugin Digest — Install Confirmation & Page Refresh

**Date:** 2026-05-15
**Scope:** Add styled confirmation modal before install, auto-refresh page after install completes.

---

<context>
The existing plugin-digest page fires `installSelected()` immediately on button click — no confirmation, no page refresh after install. Users can accidentally trigger installs, and after install the page shows stale data (installed plugin still visible in the list).
</context>

---

<constraints>

- Changes confined to `fetch_and_generate.py` — no new files
- Modal must match existing dark theme (CSS variables already defined)
- Refresh must use cached repo data — no new GitHub API call on reload
- Install flow must still work for single and multi-plugin selections
- Update flow (`doUpdate`) unchanged — no modal needed for one-click updates

</constraints>

---

<task>

## Change 1 — Styled Confirmation Modal

**Trigger:** "Install Selected" button click → show modal instead of firing immediately.

**Modal contents:**
- Dark overlay (`position:fixed`, full viewport, semi-transparent)
- Centered card listing plugin names selected for install (one per line)
- Two buttons: `Cancel` (dismiss modal, no action) and `Install N plugins` (proceed)
- While installing: both buttons disabled, Install button text becomes `Installing...` with a CSS spinner

**Implementation — HTML/CSS additions to `generate_html()`:**

```html
<!-- Confirmation modal markup (injected into body) -->
<div id="modal-overlay" class="modal-overlay" style="display:none">
  <div class="modal">
    <div class="modal-title">Install plugins?</div>
    <ul id="modal-list" class="modal-list"></ul>
    <div class="modal-actions">
      <button class="modal-cancel" onclick="closeModal()">Cancel</button>
      <button class="modal-confirm" id="modal-confirm-btn" onclick="confirmInstall()">
        Install <span id="modal-count"></span>
      </button>
    </div>
  </div>
</div>
```

**CSS additions:**
```css
.modal-overlay { position:fixed; inset:0; background:rgba(0,0,0,.6);
                 display:flex; align-items:center; justify-content:center; z-index:100; }
.modal { background:var(--surface2); border:1px solid var(--border); border-radius:12px;
         padding:1.5rem; min-width:320px; max-width:480px; }
.modal-title { font-weight:700; font-size:1rem; margin-bottom:1rem; }
.modal-list { list-style:none; margin-bottom:1.25rem; display:flex; flex-direction:column; gap:.4rem; }
.modal-list li { font-family:Consolas,monospace; font-size:.85rem; color:var(--accent); }
.modal-actions { display:flex; gap:.75rem; justify-content:flex-end; }
.modal-cancel { background:transparent; border:1px solid var(--border); color:var(--muted);
                border-radius:6px; padding:7px 16px; cursor:pointer; font-size:.85rem; }
.modal-cancel:hover { border-color:var(--text); color:var(--text); }
.modal-confirm { background:var(--green); color:#fff; border:none; border-radius:6px;
                 padding:7px 16px; cursor:pointer; font-size:.85rem; font-weight:600; }
.modal-confirm:disabled { background:var(--border); color:var(--muted); cursor:default; }
```

**JS changes:**

- `installSelected()` → renamed to `openModal()` — populates modal list, shows overlay, does NOT call `/install`
- `closeModal()` — hides overlay
- `confirmInstall()` — disables buttons, sets spinner text, calls `/install` for each selected repo, then calls `refreshPage()`

```js
let _pendingRepos = [];

function installSelected() {
  _pendingRepos = [...document.querySelectorAll('.cb:checked')].map(cb => cb.dataset.repo);
  if (!_pendingRepos.length) return;
  const list = document.getElementById('modal-list');
  list.innerHTML = _pendingRepos.map(r => `<li>${r.split('/').pop()}</li>`).join('');
  document.getElementById('modal-count').textContent = _pendingRepos.length;
  document.getElementById('modal-overlay').style.display = 'flex';
}

function closeModal() {
  document.getElementById('modal-overlay').style.display = 'none';
}

function confirmInstall() {
  const btn = document.getElementById('modal-confirm-btn');
  btn.disabled = true;
  btn.textContent = 'Installing...';
  document.querySelector('.modal-cancel').disabled = true;

  Promise.all(_pendingRepos.map(repo =>
    fetch(`http://localhost:{port}/install?repo=` + encodeURIComponent(repo))
      .then(r => r.json())
      .catch(() => ({ success: false, message: 'Network error' }))
  )).then(results => {
    closeModal();
    refreshPage();
  });
}
```

---

## Change 2 — Page Refresh After Install

**Mechanism:** After all install fetches resolve, browser calls `GET /refresh` → server regenerates HTML from cache → browser reloads.

**Server — new `/refresh` handler in `InstallHandler.do_GET`:**

```python
elif parsed.path == "/refresh":
    try:
        cache = json.loads(DIGEST_CACHE.read_text(encoding="utf-8"))
        top10_raw = cache.get("top10", [])
        needs_update = cache.get("needs_update", [])

        # Re-filter against updated installed state
        installed = get_installed_plugins()
        installed_repo_names = get_installed_repo_names(installed)
        top10 = filter_uninstalled(top10_raw, installed_repo_names)[:10]

        html = generate_html(top10, needs_update, PORT)
        DIGEST_HTML.write_text(html, encoding="utf-8")
        self._respond(200, {"success": True})
    except Exception as e:
        self._respond(500, {"success": False, "message": str(e)})
```

**Note:** `PORT` must be accessible inside `InstallHandler`. Pass it via closure when constructing the handler (same pattern as existing `make_install_handler()` factory).

**JS — `refreshPage()` function:**

```js
function refreshPage() {
  fetch(`http://localhost:{port}/refresh`)
    .then(() => location.reload())
    .catch(() => location.reload()); // reload even on error — stale > broken
}
```

---

## File Map

| File | Change |
|------|--------|
| `skills/plugin-digest/scripts/fetch_and_generate.py` | Add modal HTML/CSS/JS to `generate_html()`, rename `installSelected`, add `closeModal`/`confirmInstall`/`refreshPage`, add `/refresh` handler to `InstallHandler` |

No other files change.

</task>

---

<output>

## Success Criteria

1. Clicking "Install Selected" shows modal listing selected plugin names
2. Cancel dismisses modal, no install triggered
3. Confirm disables buttons, runs installs, then refreshes page
4. After refresh, installed plugins no longer appear in Top 10 list
5. Update flow (`doUpdate`) unchanged
6. No new GitHub API calls triggered by refresh

</output>
