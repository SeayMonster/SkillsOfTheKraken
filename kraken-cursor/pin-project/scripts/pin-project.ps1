# pin-project.ps1
# Adds the current (or specified) project to the kraken-cursor shared registry.
# Usage:
#   .\pin-project.ps1
#   .\pin-project.ps1 -Path "C:\source\repos\MyProject"

param(
    [string]$Path = (Get-Location).Path
)

$registryDir = Join-Path $env:USERPROFILE ".cursor\.kraken-cursor"
$registry    = Join-Path $registryDir "project-registry.json"
$name        = Split-Path $Path -Leaf

if (-not (Test-Path $registryDir)) {
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
}

$projects = if (Test-Path $registry) {
    Get-Content $registry -Raw -Encoding UTF8 | ConvertFrom-Json
} else { @() }

if ($projects | Where-Object { $_.rootPath -eq $Path }) {
    Write-Host "'$name' is already in the registry." -ForegroundColor Yellow
    exit 0
}

$projects += [PSCustomObject]@{ name = $name; rootPath = $Path }
$json = $projects | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($registry, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "Pinned '$name' at $Path" -ForegroundColor Green
Write-Host "Run sync-to-pm.ps1 in VS Code (kraken-cursor-desktop-vscode-bridge) to add to Project Manager." -ForegroundColor Cyan
