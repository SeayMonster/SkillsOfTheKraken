---
name: pause
description: Use when the user wants to log a paused, blocked, or in-progress task for later follow-up. Handles first-time repo setup automatically based on the user's GitHub account.
---

<context>
# Pause — Log a Paused Task

## Overview
Adds a paused work item to the user's personal GitHub-based task tracker. Auto-detects their GitHub account and sets up their repo on first use. No manual JSON editing needed.
</context>

<task>
## Steps

### 1. Detect GitHub identity
```bash
gh api user --jq '.login'
```
Store as `GH_USER`.

### 2. Find or configure the pause repo
Check for config file at `~/.claude/pause-config.json`.

- If it exists, read the `repo` field (format: `owner/repo-name`).
- If missing, run **first-time setup** (see below).

### 3. Collect item details
Ask the user for:
- **Project** — which project or area? (e.g. "Crisp Dev", "Personal")
- **Title** — what specifically is paused? (one line)
- **Notes** (optional) — where did you leave off? any context to pick it back up?

Use `AskUserQuestion` if available, otherwise ask in plain text.

### 4. Read current paused-items.json from GitHub
```bash
gh api repos/{REPO}/contents/paused-items.json --jq '{content: .content, sha: .sha}'
```
Decode the base64 content:
```bash
python -c "import base64, sys; print(base64.b64decode(sys.stdin.read().strip()).decode())" <<< "{CONTENT}"
```
Parse the JSON and append a new item:
```json
{
  "id": "<generate a lowercase uuid v4>",
  "project": "<project>",
  "title": "<title>",
  "notes": "<notes or empty string>",
  "paused_at": "<current UTC ISO timestamp, e.g. 2026-05-13T14:00:00Z>",
  "completed": false,
  "completed_at": null
}
```

### 5. Write the updated file back
Encode updated JSON and PUT via GitHub API:
```bash
python -c "
import base64, json, sys
data = json.loads(sys.stdin.read())
print(base64.b64encode(json.dumps(data, indent=2).encode()).decode())
" <<< '{UPDATED_JSON}' > /tmp/pause_encoded.txt

gh api repos/{REPO}/contents/paused-items.json \
  -X PUT \
  -f message="Pause: {TITLE}" \
  -f content="$(cat /tmp/pause_encoded.txt)" \
  -f sha="{SHA_FROM_STEP_4}"
```

### 6. Confirm
Tell the user:
> Paused **"{title}"** under **{project}**. It'll show up in tomorrow's digest.

---

## First-Time Setup

Run when `~/.claude/pause-config.json` doesn't exist:

1. Propose a repo name: `{GH_USER}sTodos` (e.g. `SeayMonster/SeaysTodos`)
2. Ask the user to confirm or provide a different name
3. Check if the repo already exists:
   ```bash
   gh repo view {GH_USER}/{REPO_NAME} --json name 2>&1
   ```
4. If not found, create it:
   ```bash
   gh repo create {GH_USER}/{REPO_NAME} --private --add-readme --description "Daily focus tracker"
   ```
5. Initialize `paused-items.json` with an empty items array (no SHA for new file):
   ```bash
   CONTENT=$(python -c "import base64; print(base64.b64encode(b'{\"items\":[]}').decode())")
   gh api repos/{GH_USER}/{REPO_NAME}/contents/paused-items.json \
     -X PUT \
     -f message="Initialize paused-items.json" \
     -f content="$CONTENT"
   ```
6. Save config:
   ```bash
   echo '{"repo":"{GH_USER}/{REPO_NAME}"}' > ~/.claude/pause-config.json
   ```
7. Continue with Step 3 (collect item details)
</task>

<constraints>
## paused-items.json structure
```json
{
  "items": [
    {
      "id": "lowercase-uuid-v4",
      "project": "Project Name",
      "title": "What is paused",
      "notes": "Context / where I left off",
      "paused_at": "2026-05-13T14:00:00Z",
      "completed": false,
      "completed_at": null
    }
  ]
}
```

## Config file — `~/.claude/pause-config.json`
```json
{"repo": "SeayMonster/SeaysTodos"}
```

## Common Mistakes
- **Wrong SHA**: always fetch the current SHA right before writing — stale SHAs cause 409 conflicts
- **New file with SHA**: omit the `sha` field entirely when creating a file for the first time
- **Base64 line breaks**: GitHub API returns base64 with newlines — strip them before decoding
- **UUID generation**: use `python -c "import uuid; print(uuid.uuid4())"` for a valid v4 UUID
</constraints>
