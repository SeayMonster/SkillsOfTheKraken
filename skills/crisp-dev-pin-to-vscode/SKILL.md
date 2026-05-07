---
name: crisp-dev-pin-to-vscode
description: Use when the user wants to register the current project so it appears in VS Code Project Manager. Triggered by phrases like "pin to VS Code", "add to VS", "register this project", or "pin in VS".
---

# Pin Project to VS Code

## Overview

Registers the current project in the shared registry so VS Code can pick it up via `crisp-dev-add-to-pm`.

## Steps

### 1 — Get the project name

Read it from the current Desktop project name (visible in the conversation context — top of the sidebar or project header). Do NOT ask the user for the name.

### 2 — Get the folder path

Check the current conversation for a file system path that was mentioned (e.g. `C:\source\repos\ClientABC`). Use it if found.

If no path has been mentioned, ask **once**:
> "What's the root folder path for this project?"

### 3 — Write to registry

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

### 4 — Tell the user

> "Pinned. Go to VS Code and run `/crisp-dev-add-to-pm` to add it to Project Manager."

## Notes

- Folder name = project name — name folders after the client
- Registry lives at `g:\My Drive\!ai\project-registry.json` (Google Drive, accessible from both tools)
- Path is the only thing Desktop can't auto-detect — once provided it's in the registry and never needed again
