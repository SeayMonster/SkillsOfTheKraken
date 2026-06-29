---
name: kraken-cursor-plugin-digest
description: >-
  Generates an HTML digest of the top 10 uninstalled Cursor plugins and skills ranked by GitHub
  stars, with one-click install and update support. Use when the user wants to discover new Cursor
  plugins, browse what's trending, check for plugin updates, or says anything like "show me popular
  Cursor skills", "what plugins should I install", or "plugin digest". Invoke with
  Use kraken-cursor-plugin-digest.
---

# kraken-cursor: plugin-digest

**Announce at start:** "I'm using kraken-cursor-plugin-digest to fetch trending Cursor plugins."

Fetch the top 10 uninstalled Cursor plugins and skill repos from GitHub by star count, generate an interactive HTML digest, and open it in the Cursor browser.

## What the page shows

- **Top 10 Discoveries** — uninstalled plugins/skills, ranked by stars. Top 3 get gold border. Check cards, then click **Install Selected** to install automatically.
- **Needs Update** — installed plugins where a newer version is available. One-click Update button. Hidden if no updates are available.

Digest state is stored under `~/.cursor/.kraken-cursor/` (`plugin-digest.html`, `plugin-digest-cache.json`).

## Pre-flight

1. Resolve `{SKILL_DIR}` = directory containing this skill's `SKILL.md`.
2. Python 3.10+ available on PATH.

## Steps

### Step 1 — Run the script

```bash
python "{SKILL_DIR}/scripts/fetch_and_generate.py"
```

Flags:

- No flags: fetch fresh from GitHub, generate HTML, start local install server
- `--cached`: skip GitHub fetch, use cached results (offline/fast)

The script writes `~/.cursor/.kraken-cursor/plugin-digest.html` and prints the absolute path. It starts a local HTTP server for one-click install actions (runs up to 30 minutes or until Ctrl+C).

Do **not** rely on the script's optional system-browser open — use Cursor browser MCP (next step).

### Step 2 — Open in Cursor browser

Use the **cursor-ide-browser** MCP server. Read tool schemas under the MCP descriptors before calling.

1. Convert the printed absolute path to a `file:///` URL (forward slashes, URL-encoded spaces).
2. `browser_navigate` — open the digest HTML URI.
3. `browser_lock` with `action: "lock"` — lock the tab after navigate.
4. `browser_snapshot` — confirm the digest loaded (header, plugin cards, Install Selected button).
5. `browser_lock` with `action: "unlock"` — release when done.

Do **not** use Claude-only browser MCP servers; use cursor-ide-browser only.

### Step 3 — Tell the user

Summarize what loaded: count of discoveries, whether cached results were used (rate limit/offline), and that they can check plugins and click **Install Selected**. Remind them the install server must stay running while they use one-click install.

## Error handling

- **GitHub rate limit**: script shows last cached results with a warning; mention this to the user.
- **No internet**: uses cached results if available; if no cache, stop and ask user to retry later.
- **Install fails**: inline error on the card; offer manual install via **kraken-cursor-register-skill-repo** or **kraken-cursor-add-marketplace**.
