# sync-to-pm.ps1
# Reads the kraken-cursor shared project registry and adds missing entries to VS Code Project Manager.
# Run in VS Code after pinning a project from Cursor (kraken-cursor-pin-project).

$registry = Join-Path $env:USERPROFILE ".cursor\.kraken-cursor\project-registry.json"
$pmPath   = Join-Path $env:APPDATA "Code\User\globalStorage\alefragnani.project-manager\projects.json"

if (-not (Test-Path $registry)) {
    Write-Host "No project registry found at $registry" -ForegroundColor Yellow
    Write-Host "Pin a project from Cursor first (Use kraken-cursor-pin-project)." -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path $pmPath)) {
    Write-Host "ERROR: VS Code Project Manager not found. Install the 'Project Manager' extension." -ForegroundColor Red
    exit 1
}

$source     = Get-Content $registry -Raw -Encoding UTF8 | ConvertFrom-Json
$pmProjects = Get-Content $pmPath -Raw -Encoding UTF8 | ConvertFrom-Json

$added = 0
foreach ($proj in $source) {
    $exists = $pmProjects | Where-Object { $_.rootPath -eq $proj.rootPath -or $_.name -eq $proj.name }
    if (-not $exists) {
        $pmProjects += [PSCustomObject]@{
            name     = $proj.name
            rootPath = $proj.rootPath
            paths    = @()
            tags     = @()
            enabled  = $true
            profile  = ""
        }
        Write-Host "Added: $($proj.name)" -ForegroundColor Green
        $added++
    }
}

if ($added -gt 0) {
    $json = $pmProjects | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($pmPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "$added project(s) added to VS Code Project Manager." -ForegroundColor Cyan
    Write-Host "Reload VS Code window (Ctrl+Shift+P -> Reload Window) to see changes." -ForegroundColor Cyan
} else {
    Write-Host "Project Manager already up to date." -ForegroundColor Yellow
}
