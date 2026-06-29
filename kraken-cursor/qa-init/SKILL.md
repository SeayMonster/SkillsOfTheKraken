---
name: kraken-cursor-qa-init
description: >-
  Initializes a QA bot workspace for the current client repository in the QA
  Bots repo. Auto-detects .sln, infers client name from folder name, scaffolds
  workspace with .claude and .cursor config. Use when the user asks to initialize
  QA bots, set up qa-init, scaffold a QA workspace, or run kraken-cursor-qa-init
  from a client repo in Cursor.
argument-hint: [optional: client-name-override]
---

# kraken-cursor: qa-init

**Announce at start:** "I'm using kraken-cursor-qa-init to initialize the QA bot workspace."

Initializes a QA bot workspace for this client repository.

## Pre-flight

1. Find the QA Bots repo path. Check in this order:
   - Read file `~/.cursor/.kraken-cursor/qa-bots-path` (a single line containing the absolute path)
   - If file does not exist: ask the user "Where is your QA Bots repo?" then write their answer to `~/.cursor/.kraken-cursor/qa-bots-path` (create parent directories if needed) and continue.

Store this path as `QA_BOTS_REPO` for all steps below.

## Step 1: Detect Solution File

Glob `*.sln` in the current working directory (non-recursive first, then recursive to depth 2 if none found at root).

- Exactly one found: use it. Note the full path.
- Multiple found: list them numbered. Ask "Which solution? [1/2/...]". Use the selected one.
- None found: ask "No .sln found. Enter the full path to the solution file:". Use the provided path.

## Step 2: Determine Client Name

- If argument `$0` was provided: use `$0` as the client name.
- Otherwise: use the current folder name (run `Split-Path -Leaf (Get-Location)` in PowerShell).
- Show: `Client name: <name>. Press Enter to confirm or type a new name:` (blank = keep default).
- Clean the name: lowercase, replace spaces with hyphens, remove special characters except `-` and `_`.

## Step 3: Check for Collision

Check if `QA_BOTS_REPO\clients\<name>` already exists.

- If it does: append `-2` (or `-3`, etc. until unique). Notify user: `Note: Using name <new-name> to avoid collision.`

## Step 4: Scaffold Client Workspace

Run these PowerShell commands (replace `<name>`, `<solution-path>`, and `QA_BOTS_REPO` with actual values):

```powershell
$clientDir = "QA_BOTS_REPO\clients\<name>"
New-Item -ItemType Directory -Force "$clientDir"
New-Item -ItemType Directory -Force "$clientDir\.claude"
New-Item -ItemType Directory -Force "$clientDir\.claude\skills"
New-Item -ItemType Directory -Force "$clientDir\.cursor"
New-Item -ItemType Directory -Force "$clientDir\.qa-run"

# CLAUDE.md from template with replacements
$claudeMd = Get-Content "QA_BOTS_REPO\_shared\templates\CLAUDE.md" -Raw
$claudeMd = $claudeMd -replace "\{\{client_name\}\}", "<name>"
$claudeMd = $claudeMd -replace "\{\{solution_path\}\}", "<solution-path>"
Set-Content "$clientDir\CLAUDE.md" $claudeMd -Encoding UTF8

# qa-config.json — Claude Code compatibility
Set-Content "$clientDir\.claude\qa-config.json" '{ "solution_path": "<solution-path>" }' -Encoding UTF8

# qa-config.json — Cursor
Set-Content "$clientDir\.cursor\qa-config.json" '{ "solution_path": "<solution-path>" }' -Encoding UTF8

# Copy shared skills
Copy-Item -Recurse "QA_BOTS_REPO\_shared\skills\*" "$clientDir\.claude\skills\" -Force

# Copy report template
Copy-Item "QA_BOTS_REPO\_shared\templates\report.html" "$clientDir\.qa-run\report.html" -Force
```

## Step 5: Print Success

```
QA workspace created

  Client:    <name>
  Solution:  <solution-path>
  Workspace: QA_BOTS_REPO\clients\<name>\

Use kraken-cursor-qa-run to start QA analysis.
```

## Error Handling

- If `_shared\templates\CLAUDE.md` not found in QA_BOTS_REPO: "QA Bots repo structure is missing _shared/templates. Run git pull in your QA Bots repo."
- If write fails due to permissions: surface the PowerShell error directly.
