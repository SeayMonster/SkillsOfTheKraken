---
name: crisp-dev-desktop-vscode-bridge
description: Use when working across Claude Desktop and VS Code on the same projects, registering a new project so it appears in both tools, or syncing projects between Claude Desktop and VS Code Project Manager.
---

# Claude Desktop ↔ VS Code Bridge

## Overview

Desktop is for planning and fast multi-project switching. VS Code is for coding. A shared registry file (`g:\My Drive\!ai\project-registry.json`) keeps both tools in sync. Root folder names are the project names — name folders after the client.

## Registering a New Project (Desktop)

When the user says "register this project" or "add this to project manager":

1. Ask for the root folder path if not already provided
2. Extract the folder name from the path (last segment)
3. Run this PowerShell to append to the registry:

```powershell
$registry = "g:\My Drive\!ai\project-registry.json"
$name = Split-Path "C:\source\repos\ClientABC" -Leaf
$path = "C:\source\repos\ClientABC"

$projects = if (Test-Path $registry) {
    Get-Content $registry -Raw -Encoding UTF8 | ConvertFrom-Json
} else { @() }

$exists = $projects | Where-Object { $_.rootPath -eq $path }
if (-not $exists) {
    $projects += [PSCustomObject]@{ name = $name; rootPath = $path }
    $json = $projects | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($registry, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Registered '$name' in project registry."
} else {
    Write-Host "'$name' already in registry."
}
```

4. Remind the user: **open VS Code and run `sync-to-pm.ps1`** to add it to Project Manager.

## Syncing to VS Code Project Manager

Run `sync-to-pm.ps1` in VS Code (or from any terminal) after registering a new project in Desktop.

The script reads the shared registry and adds any missing entries to VS Code PM.

## When to Use Each Tool

| Task | Use |
|------|-----|
| Planning, brainstorming, Q&A | Desktop |
| Writing/editing code | VS Code |
| Multi-project context switching | Desktop |
| Running terminal commands | VS Code |
| Background processing while switching projects | Desktop |

## Key Behavioral Differences

| | Desktop | VS Code |
|---|---|---|
| Project switch speed | Instant | Slow (full reload) |
| Background processing | Continues | Killed on switch |
| File editing | No (shell workaround) | Native |
| Identify current project | Sidebar list | Status bar (bottom) |

## Recommended Workflow

1. Create client folder — use the client name as the folder name
2. In Desktop: register the project with the skill → it writes to the registry
3. In VS Code: run `sync-to-pm.ps1` → project appears in Project Manager
4. Create matching Desktop project with same client name for conversation history
