---
description: Initialize a QA bot workspace for the current client repository. Auto-detects .sln, infers client name from folder name, scaffolds workspace in QA Bots repo. Run from the client repo in Claude Code.
argument-hint: [optional: client-name-override]
---

You are initializing a QA bot workspace for this client repository.

## Prerequisites Check

1. Find the QA Bots repo path. Check in this order:
   - Read file `~/.claude/.qa-bots-path` (a single line containing the path)
   - If file does not exist: ask the user "Where is your QA Bots repo? (e.g. C:\Users\you\source\repos\QA Bots)" then write their answer to `~/.claude/.qa-bots-path` and continue.

Store this path as QA_BOTS_REPO for all steps below.

## Step 1: Detect Solution File

Glob `*.sln` in the current working directory (non-recursive first, then recursive to depth 2 if none found at root).

- Exactly one found: use it. Note the full path.
- Multiple found: list them numbered. Ask "Which solution? [1/2/...]". Use the selected one.
- None found: ask "No .sln found. Enter the full path to the solution file:". Use the provided path.

## Step 2: Determine Client Name

- If argument $0 was provided: use $0 as the client name.
- Otherwise: use the current folder name (run `Split-Path -Leaf (Get-Location)` in PowerShell).
- Show: `Client name: <name>. Press Enter to confirm or type a new name:` (blank = keep default).
- Clean the name: lowercase, replace spaces with hyphens, remove special characters except `-` and `_`.

## Step 3: Check for Collision

Check if `QA_BOTS_REPO\clients\<name>` already exists.
- If it does: append `-2` (or `-3`, etc. until unique). Notify user: `Note: Using name <new-name> to avoid collision.`

## Step 4: Scaffold Client Workspace

Run these PowerShell commands (replace <name> and <solution-path> with actual values):

```powershell
$clientDir = "QA_BOTS_REPO\clients\<name>"
New-Item -ItemType Directory -Force "$clientDir"
New-Item -ItemType Directory -Force "$clientDir\.claude"
New-Item -ItemType Directory -Force "$clientDir\.claude\skills"
New-Item -ItemType Directory -Force "$clientDir\.qa-run"

# CLAUDE.md from template with replacements
$claudeMd = Get-Content "QA_BOTS_REPO\_shared\templates\CLAUDE.md" -Raw
$claudeMd = $claudeMd -replace "\{\{client_name\}\}", "<name>"
$claudeMd = $claudeMd -replace "\{\{solution_path\}\}", "<solution-path>"
Set-Content "$clientDir\CLAUDE.md" $claudeMd -Encoding UTF8

# qa-config.json
Set-Content "$clientDir\.claude\qa-config.json" '{ "solution_path": "<solution-path>" }' -Encoding UTF8

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

Run crisp-tc:qa-run to start QA analysis.
```

## Error Handling

- If `_shared\templates\CLAUDE.md` not found in QA_BOTS_REPO: "QA Bots repo structure is missing _shared/templates. Run git pull in your QA Bots repo."
- If write fails due to permissions: surface the PowerShell error directly.
