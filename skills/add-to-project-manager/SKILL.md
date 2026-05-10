---
name: add-to-project-manager
description: Use when the user wants to add a pinned project to VS Code Project Manager. Triggered by phrases like "add to PM", "add to project manager", or after running crisp-dev-pin-to-vscode in Desktop.
---

# Add to VS Code Project Manager

## Overview

Reads the shared registry and adds any missing projects to VS Code Project Manager.

## Steps

Run this PowerShell — no prompts needed:

```powershell
$registry = "g:\My Drive\!ai\project-registry.json"
$pmPath   = "$env:APPDATA\Code\User\globalStorage\alefragnani.project-manager\projects.json"

if (-not (Test-Path $registry)) {
    Write-Host "No registry found. Go to Claude Desktop and run /crisp-dev-pin-to-vscode first."
    exit
}

$source     = Get-Content $registry -Raw -Encoding UTF8 | ConvertFrom-Json
$pmProjects = Get-Content $pmPath   -Raw -Encoding UTF8 | ConvertFrom-Json

$added = 0
foreach ($proj in $source) {
    if (-not ($pmProjects | Where-Object { $_.rootPath -eq $proj.rootPath })) {
        $pmProjects += [PSCustomObject]@{
            name     = $proj.name
            rootPath = $proj.rootPath
            paths    = @()
            tags     = @()
            enabled  = $true
            profile  = ""
        }
        Write-Host "Added: $($proj.name)"
        $added++
    }
}

if ($added -gt 0) {
    $json = $pmProjects | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($pmPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "$added project(s) added. Reload VS Code (Ctrl+Shift+P -> Reload Window) to see them."
} else {
    Write-Host "Project Manager already up to date."
}
```

## Notes

- Projects come from `g:\My Drive\!ai\project-registry.json`
- Safe to run multiple times — skips entries already in PM
