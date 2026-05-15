---
name: todos
description: Use when the user wants to view their paused tasks, open their focus dashboard, or see what's on pause. Generates and opens the HTML digest locally on demand.
---

<context>
# Todos — View Paused Tasks

## Overview
Fetches paused items from the user's GitHub tracker, generates a fresh HTML digest, and opens it in their browser. Works anytime — no need to wait for the morning routine.
</context>

<task>
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
Generate a self-contained HTML file at a stable path: `~/.claude/todos-digest.html`

The page has **two tabs**: **Focus** (incomplete items) and **History** (completed items). Active tab persists via localStorage key `"active-tab"`.

**Focus tab:**
- Incomplete items (`"completed": false`)
- Each item: checkbox (JS + localStorage, keyed by `id`), bold title, smaller notes, muted "paused [date]" label
- Checkboxes persist via localStorage on refresh
- Group items by `project` field with count in section header
- If no incomplete items: show "All caught up! Nothing on pause."

**History tab:**
- Completed items (`"completed": true`)
- Static filled checkbox, strikethrough title, "completed [date]" label
- If no completed items: show "No completed items yet."

Both tabs share style: dark mode, no external deps, single file. Header: **"Today's Focus — [Day, Month Date, Year]"**. Footer: "To permanently archive: edit paused-items.json on GitHub and set completed: true". Bottom note: "Run /pause to add a new paused item".

**Write the file using the Write tool** (not inline Python — bash quote-escaping corrupts single quotes inside HTML/JS):

Use the Write tool to write directly to the file path returned by:
```bash
python -c "import pathlib; print(pathlib.Path.home().joinpath('.claude/todos-digest.html'))"
```

### 4. Open in browser
```bash
python -c "import webbrowser, pathlib; webbrowser.open(pathlib.Path.home().joinpath('.claude/todos-digest.html').as_uri())"
```

### 5. Confirm
Tell the user how many incomplete items were found:
> Opened your focus dashboard — **{N} item(s)** on pause.

Or if zero:
> Opened your focus dashboard — you're all caught up!
</task>

<constraints>
## Common Mistakes
- **Base64 line breaks**: strip newlines before decoding — GitHub API wraps base64 at 60 chars
- **Path separators on Windows**: use `pathlib.Path` not string concatenation for cross-platform paths
- **localStorage key conflicts**: use item `id` as the localStorage key, not title (titles can repeat)
- **Stale checked state**: localStorage persists checked items across days — that's intentional (session-level tracking)
- **Inline Python HTML writing**: bash quote-escaping corrupts single quotes inside HTML/JS — always use Write tool to write the HTML file
</constraints>
