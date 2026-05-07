---
name: crisp-dev-pin-to-vscode
description: Use when the user wants to register the current project so it appears in VS Code Project Manager. Triggered by phrases like "pin to VS Code", "add to VS", "register this project", or "pin in VS".
---

# Pin Project to VS Code

## Overview

Registers the current project in the shared registry so VS Code can pick it up via `crisp-dev-add-to-pm`.

## Steps

1. Ask the user for the root folder path if they haven't provided it:
   > "What's the root folder path for this project?"

2. Run this PowerShell — uses the folder name as the project name:

```powershell
$registry = "g:\My Drive\!ai\project-registry.json"
$path = "REPLACE_WITH_PATH"
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

3. Tell the user: **go to VS Code and run `/crisp-dev-add-to-pm`** to finish.

## Notes

- Folder name = project name, so name your folders after the client
- Registry lives at `g:\My Drive\!ai\project-registry.json` (Google Drive, accessible from both tools)
