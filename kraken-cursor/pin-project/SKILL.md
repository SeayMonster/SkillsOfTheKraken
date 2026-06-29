---
name: kraken-cursor-pin-project
description: >-
  Registers the current project in the shared kraken-cursor project registry so
  VS Code Project Manager can pick it up via kraken-cursor-desktop-vscode-bridge.
  Use when the user asks to pin to VS Code, add to VS, register this project,
  or pin in VS from Cursor. Invoke with Use kraken-cursor-pin-project.
---

# kraken-cursor: pin-project

**Announce at start:** "I'm using kraken-cursor-pin-project to register this project."

Registers the current working directory in the shared registry at `~/.cursor/.kraken-cursor/project-registry.json`. VS Code picks up entries via **Use kraken-cursor-desktop-vscode-bridge** (`sync-to-pm.ps1`).

Works from Cursor Agent, VS Code terminal, or any shell — no prompts needed.

## Pre-flight

1. Resolve `{repoRoot}` = folder to register (default: current working directory).
2. Folder name becomes the project name — name client folders after the client.

## Steps

Run `{SKILL_DIR}/scripts/pin-project.ps1` with `-Path` set to `{repoRoot}`:

```powershell
& "{SKILL_DIR}/scripts/pin-project.ps1" -Path (Get-Location).Path
```

Or from the skill directory:

```powershell
.\scripts\pin-project.ps1
```

Tell the user the name and path that were registered, then:

> "Open VS Code and run **Use kraken-cursor-desktop-vscode-bridge** (sync step), or run `{SKILL_DIR}/../desktop-vscode-bridge/scripts/sync-to-pm.ps1` to add it to Project Manager."

## Notes

- Folder name = project name — name folders after the client
- Registry: `~/.cursor/.kraken-cursor/project-registry.json` (shared between Cursor and VS Code workflows)
- Safe to re-run — skips if the path is already registered
