---
name: crisp-dev-desktop-vscode-bridge
description: Use when working across Claude Desktop and VS Code on the same projects, switching between planning and coding, or when projects need to stay in sync between both tools.
---

# Claude Desktop ↔ VS Code Bridge

## Overview

Claude Desktop and VS Code Claude Code serve different roles. Desktop is fast for planning and multi-project chat. VS Code has file access and terminal for actual coding. This skill covers the workflow for using both together and keeping projects synced.

## When to Use Each Tool

| Task | Use |
|------|-----|
| Planning, brainstorming, Q&A | Desktop |
| Writing/editing code | VS Code |
| Multi-project context switching | Desktop |
| Running terminal commands | VS Code |
| Background processing (keep running while you switch) | Desktop |
| Deep single-project work | VS Code |

## Key Behavioral Differences

| | Desktop | VS Code |
|---|---|---|
| Project switch speed | Instant | Slow (full reload) |
| Background processing | Continues | Killed on switch |
| File editing | No (shell workaround) | Native |
| Know which project | Sidebar list | Title bar / status bar |
| Multi-project simultaneous | Yes | Needs 2 windows |

## Project Sync: VS Code PM ↔ Desktop

**VS Code Project Manager** is the source of truth for local project paths.
**Claude Desktop projects** are cloud conversation workspaces — matched by name convention.

### Naming Convention

Use the **same name** in both tools so you can instantly match them:
- PM project name: `CKB Planogram Import Export`
- Desktop project name: `CKB Planogram Import Export`

### Register a New Project

Use `register-project.ps1` to add a project to VS Code PM from anywhere:

```powershell
# Add a project
.\register-project.ps1 -Name "My Project" -Path "C:\source\repos\MyProject"

# List all registered projects
.\register-project.ps1 -List
```

Then create a matching project in Claude Desktop with the same name.

### Identifying Your Current Project

- **VS Code**: Look at the **status bar** (bottom of window) — shows workspace name
- **Desktop**: Look at the **sidebar** — active project is highlighted
- **VS Code title bar**: Shows full folder path if status bar is ambiguous

## Recommended Workflow

1. **Plan in Desktop** — fast switching, no reload friction
2. **Bring plan to VS Code** — open the matching project via Project Manager
3. **Build in VS Code** — file edits, terminal commands, Claude Code
4. **Switch back to Desktop** to plan next phase or work a different project

## Setup: GitHub Connector in Desktop

Required for skill marketplace access:
1. Desktop → Settings → Connections → GitHub → Sign in
2. Browser opens → authenticate with company Google account
3. If already logged into GitHub in browser, approves automatically
