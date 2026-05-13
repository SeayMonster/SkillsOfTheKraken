---
name: todos
description: Use when the user wants to view their paused tasks, open their focus dashboard, or see what's on pause. Generates and opens the HTML digest locally on demand.
---

# Todos — View Paused Tasks

## Overview
Fetches paused items from the user's GitHub tracker, generates a fresh HTML digest, and opens it in their browser. Works anytime — no need to wait for the morning routine.

## Steps

### 1. Find the pause repo
Read `~/.claude/pause-config.json` for the `repo` field (e.g. `SeayMonster/SeaysTodos`).

If missing, tell the user: "No pause repo configured. Run `/pause` first to set one up."

### 2. Fetch paused-items.json
```bash
gh api repos/{REPO}/contents/paused-items.json --jq '.content'
```
Decode from base64:
```bash
python -c "import base64,sys; print(base64.b64decode(sys.stdin.read().strip().replace('\n','')).decode())" <<< "{CONTENT}"
```

### 3. Generate HTML
Filter to `"completed": false` items. Generate a self-contained HTML file at a stable path: `~/.claude/todos-digest.html`

The HTML must:
- Match the style of the morning digest (dark mode, no external deps, single file)
- Show today's date in the header: **"Today's Focus — [Day, Month Date, Year]"**
- Group items by `project` field
- Each item: checkbox (JS + localStorage, keyed by `id`), bold title, smaller notes, muted "paused [date]" label
- Checkboxes persist via localStorage on refresh
- Show item count per project in the section header
- If no incomplete items: show a clean "All caught up! Nothing on pause." page
- Footer: "To permanently archive: edit paused-items.json on GitHub and set completed: true"
- Show a **"Add item"** note at the bottom: "Run /pause to add a new paused item"

Write the file:
```bash
python -c "
content = '''...html...'''
with open('C:/Users/{USER}/.claude/todos-digest.html', 'w', encoding='utf-8') as f:
    f.write(content)
"
```
Get the home path dynamically: `python -c "import pathlib; print(pathlib.Path.home())"` 

### 4. Open in browser
```bash
python -c "import webbrowser, pathlib; webbrowser.open(pathlib.Path.home().joinpath('.claude/todos-digest.html').as_uri())"
```

### 5. Confirm
Tell the user how many incomplete items were found:
> Opened your focus dashboard — **{N} item(s)** on pause.

Or if zero:
> Opened your focus dashboard — you're all caught up!

---

## Common Mistakes
- **Base64 line breaks**: strip newlines before decoding — GitHub API wraps base64 at 60 chars
- **Path separators on Windows**: use `pathlib.Path` not string concatenation for cross-platform paths
- **localStorage key conflicts**: use item `id` as the localStorage key, not title (titles can repeat)
- **Stale checked state**: localStorage persists checked items across days — that's intentional (session-level tracking)
