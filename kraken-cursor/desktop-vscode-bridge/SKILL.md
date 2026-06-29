---
name: kraken-cursor-desktop-vscode-bridge
description: >-
  Workflow for using Cursor and VS Code together on the same projects — planning
  in Cursor, coding in VS Code, and keeping Project Manager in sync. Use when
  switching between Cursor agent work and VS Code/Copilot, syncing projects, or
  registering repos in VS Code Project Manager. Invoke with Use kraken-cursor-desktop-vscode-bridge.
---

# kraken-cursor: desktop-vscode-bridge

**Announce at start:** "I'm using kraken-cursor-desktop-vscode-bridge for Cursor ↔ VS Code project sync."

Cursor and VS Code serve different roles on the same client repos. Cursor runs kraken-cursor agent skills, multi-step orchestration, and MCP integrations. VS Code (often with Copilot-only SaaS setups) handles traditional IDE workflows and Project Manager bookmarks.

## When to Use Each Tool

| Task | Use |
|------|-----|
| Kraken agent skills, QA bots, deploy packaging | Cursor |
| Planning, spec review, multi-step orchestration | Cursor |
| Copilot-only dev (no Cursor agent) | VS Code |
| Visual Studio debugging alongside VS Code | VS Code |
| Project Manager bookmarks for quick folder open | VS Code |
| Running terminal + file edits with kraken skills | Cursor |

## Key Behavioral Differences

| | Cursor | VS Code |
|---|---|---|
| Kraken skills | `kraken-cursor-*` via agent | `.github/copilot-instructions.md` via Copilot |
| Workspace switch | Moderate (MCP reload on restart) | Slow (full window reload) |
| Agent background work | Task subagents can continue | N/A |
| File editing | Native | Native |
| Know which project | Window title / workspace folder | Status bar / Project Manager |
| Multi-project simultaneous | Multiple Cursor windows | Multiple VS Code windows |

## Project Sync: Shared Registry ↔ VS Code PM

**VS Code Project Manager** is the source of truth for local IDE bookmarks.
**Shared registry** (`~/.cursor/.kraken-cursor/project-registry.json`) bridges Cursor pin actions to VS Code.

### Naming Convention

Use the **same folder name** everywhere so projects match instantly:

- Registry / PM name: `CKB Planogram Import Export`
- Cursor workspace: open the same folder path
- VS Code PM entry: same name and `rootPath`

### Register a New Project

**From Cursor** — use **Use kraken-cursor-pin-project** (writes to shared registry).

**Direct to VS Code PM** — run `{SKILL_DIR}/scripts/register-project.ps1`:

```powershell
# Add a project
& "{SKILL_DIR}/scripts/register-project.ps1" -Name "My Project" -Path "C:\source\repos\MyProject"

# List all registered projects
& "{SKILL_DIR}/scripts/register-project.ps1" -List
```

Then open the same folder in Cursor (**File → Open Folder**) so agent context matches.

### Sync Registry → Project Manager

After pinning from Cursor, run in VS Code (or from a terminal with VS Code PM installed):

```powershell
& "{SKILL_DIR}/scripts/sync-to-pm.ps1"
```

Reload the VS Code window if new entries do not appear (**Ctrl+Shift+P → Reload Window**).

### Identifying Your Current Project

- **Cursor**: Window title and Explorer root folder
- **VS Code**: Status bar (bottom) shows workspace name; title bar shows full path if ambiguous
- **Project Manager sidebar**: Lists all bookmarked projects by name

## Recommended Workflow

1. **Plan in Cursor** — spec review, QA init, deploy packaging, agent orchestration
2. **Pin the project** — **Use kraken-cursor-pin-project** if not already in registry
3. **Sync to VS Code** — run `sync-to-pm.ps1`, open via Project Manager
4. **Build in VS Code** — Copilot-assisted coding with committed `copilot-instructions.md`
5. **Return to Cursor** for the next kraken-cursor skill or a different client repo

## Copilot Setup in VS Code

If the repo lacks `.github/copilot-instructions.md`, run **Use kraken-cursor-setup-copilot** from Cursor (or follow that skill inline) before relying on Copilot in VS Code.

## Scripts

| Script | Purpose |
|--------|---------|
| `{SKILL_DIR}/scripts/register-project.ps1` | Add directly to VS Code Project Manager |
| `{SKILL_DIR}/scripts/sync-to-pm.ps1` | Import shared registry entries into Project Manager |
