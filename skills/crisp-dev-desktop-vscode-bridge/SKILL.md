---
name: crisp-dev-desktop-vscode-bridge
description: Use when working across Claude Desktop and VS Code on the same projects, registering a new project so it appears in both tools, or syncing projects between Claude Desktop and VS Code Project Manager.
---

# Claude Desktop ↔ VS Code Bridge

## Overview

Desktop is for planning and fast multi-project switching. VS Code is for coding. A shared registry file (`g:\My Drive\!ai\project-registry.json`) keeps both tools in sync. Root folder names are the project names — name folders after the client.

## Registering the Current Project

### In VS Code (auto-detect)

Claude knows the current working directory. Run this immediately — no need to ask for a path:

```powershell
$registry = "g:\My Drive\!ai\project-registry.json"
$path = (Get-Location).Path
$name = Split-Path $path -Leaf

$projects = if (Test-Path $registry) {
    Get-Content $registry -Raw -Encoding UTF8 | ConvertFrom-Json
} else { @() }

$exists = $projects | Where-Object { $_.rootPath -eq $path }
if (-not $exists) {
    $projects += [PSCustomObject]@{ name = $name; rootPath = $path }
    $json = $projects | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($registry, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Registered '$name' -> $path"
} else {
    Write-Host "'$name' already in registry."
}
```

Then run `sync-to-pm.ps1` to push the new entry into VS Code Project Manager.

### In Desktop (provide path)

Desktop has no working directory — ask the user for the root folder path, then:

```powershell
$registry = "g:\My Drive\!ai\project-registry.json"
$path = "PASTE_PATH_HERE"
$name = Split-Path $path -Leaf

$projects = if (Test-Path $registry) {
    Get-Content $registry -Raw -Encoding UTF8 | ConvertFrom-Json
} else { @() }

$exists = $projects | Where-Object { $_.rootPath -eq $path }
if (-not $exists) {
    $projects += [PSCustomObject]@{ name = $name; rootPath = $path }
    $json = $projects | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($registry, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Registered '$name'. Now open VS Code and run sync-to-pm.ps1."
} else {
    Write-Host "'$name' already in registry."
}
```

## Syncing to VS Code Project Manager

Run `sync-to-pm.ps1` after registering. It reads the registry and adds missing entries to PM.

## When to Use Each Tool

| Task | Use |
|------|-----|
| Planning, brainstorming, Q&A | Desktop |
| Writing/editing code | VS Code |
| Multi-project context switching | Desktop |
| Running terminal commands | VS Code |
| Background processing while switching | Desktop |

## Key Behavioral Differences

| | Desktop | VS Code |
|---|---|---|
| Project switch speed | Instant | Slow (full reload) |
| Background processing | Continues | Killed on switch |
| File editing | No (shell workaround) | Native |
| Identify current project | Sidebar list | Status bar (bottom) |

## Recommended Workflow

1. Create client folder — name it after the client
2. Open in VS Code → run this skill → project auto-registers
3. Run `sync-to-pm.ps1` → appears in Project Manager
4. Create matching Desktop project with same client name
