---
name: crisp-dev-pin-to-vscode
description: Use when the user wants to register the current project so it appears in VS Code Project Manager. Triggered by phrases like "pin to VS Code", "add to VS", "register this project", or "pin in VS".
---

# Pin Project to VS Code

## Overview

Registers the current working directory in the shared registry so VS Code can pick it up via `crisp-dev-add-to-pm`. Works in Claude Code whether running inside Desktop or VS Code.

## Steps

Run this immediately — no prompts needed:

```powershell
$registry = "g:\My Drive\!ai\project-registry.json"
$path = (Get-Location).Path
$name = Split-Path $path -Leaf

$projects = if (Test-Path $registry) {
    Get-Content $registry -Raw -Encoding UTF8 | ConvertFrom-Json
} else { @() }

if ($projects | Where-Object { $_.rootPath -eq $path }) {
    Write-Host "'$name' is already in the registry."
} else {
    $projects += [PSCustomObject]@{ name = $name; rootPath = $path }
    $json = $projects | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($registry, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Pinned '$name'. Now go to VS Code and run /crisp-dev-add-to-pm."
}
```

Tell the user the name and path that were registered, then:
> "Run `/crisp-dev-add-to-pm` in VS Code to add it to Project Manager."

## Notes

- Folder name = project name — name folders after the client
- Registry lives at `g:\My Drive\!ai\project-registry.json` (Google Drive, accessible from both tools)
