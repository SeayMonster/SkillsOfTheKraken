# register-project.ps1
# Adds a project to VS Code Project Manager from anywhere (Cursor, VS Code terminal, etc.)
# Usage:
#   .\register-project.ps1 -Name "My Project" -Path "C:\source\repos\MyProject"
#   .\register-project.ps1 -List

param(
    [string]$Name,
    [string]$Path,
    [switch]$List
)

$pmPath = Join-Path $env:APPDATA "Code\User\globalStorage\alefragnani.project-manager\projects.json"

if (-not (Test-Path $pmPath)) {
    Write-Host "ERROR: VS Code Project Manager not found. Install the 'Project Manager' extension first." -ForegroundColor Red
    exit 1
}

$projects = Get-Content $pmPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($List) {
    Write-Host "Registered projects:" -ForegroundColor Cyan
    $projects | ForEach-Object { Write-Host "  $($_.name) -> $($_.rootPath)" }
    exit 0
}

if (-not $Name -or -not $Path) {
    Write-Host "Usage: register-project.ps1 -Name 'Project Name' -Path 'C:\path\to\project'" -ForegroundColor Yellow
    Write-Host "       register-project.ps1 -List" -ForegroundColor Yellow
    exit 1
}

$existing = $projects | Where-Object { $_.name -eq $Name -or $_.rootPath -eq $Path }
if ($existing) {
    Write-Host "Project already registered: $($existing.name)" -ForegroundColor Yellow
    exit 0
}

$newProject = [PSCustomObject]@{
    name     = $Name
    rootPath = $Path
    paths    = @()
    tags     = @()
    enabled  = $true
    profile  = ""
}

$projects += $newProject
$json = $projects | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($pmPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "Added '$Name' to VS Code Project Manager." -ForegroundColor Green
Write-Host "Open the same folder in Cursor (File -> Open Folder) so agent context matches." -ForegroundColor Cyan
