# SkillsOfTheKraken - Claude Desktop Installer
# Run this once to add the skill marketplace to your Claude Desktop settings.
# Usage: Right-click -> "Run with PowerShell"  OR  paste into a terminal:
#   irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/addclaudeskills.ps1 | iex

$marketplaceKey  = "SkillsOfTheKraken"
$marketplaceRepo = "SeayMonster/SkillsOfTheKraken"
$settingsPath    = "$env:USERPROFILE\.claude\settings.json"
$knownMktsPath   = "$env:USERPROFILE\.claude\plugins\known_marketplaces.json"
$pluginsDir      = "$env:USERPROFILE\.claude\plugins"

function Write-Json($obj, $path) {
    $json = $obj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

# Ensure directories exist
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude" -Force | Out-Null
New-Item -ItemType Directory -Path $pluginsDir               -Force | Out-Null

# --- settings.json ---
if (Test-Path $settingsPath) {
    try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json }
    catch {
        Write-Host "ERROR: settings.json is invalid JSON. Fix it manually first." -ForegroundColor Red
        exit 1
    }
} else {
    $settings = [PSCustomObject]@{}
}

if (-not $settings.PSObject.Properties["extraKnownMarketplaces"]) {
    $settings | Add-Member -MemberType NoteProperty -Name "extraKnownMarketplaces" -Value ([PSCustomObject]@{})
}

if (-not $settings.extraKnownMarketplaces.PSObject.Properties[$marketplaceKey]) {
    $settings.extraKnownMarketplaces | Add-Member -MemberType NoteProperty -Name $marketplaceKey -Value ([PSCustomObject]@{
        source = [PSCustomObject]@{ source = "github"; repo = $marketplaceRepo }
    })
    Write-Json $settings $settingsPath
    Write-Host "Added to settings.json" -ForegroundColor Green
} else {
    Write-Host "Already in settings.json" -ForegroundColor Yellow
}

# --- known_marketplaces.json (required for Claude Desktop to show the marketplace) ---
if (Test-Path $knownMktsPath) {
    try { $km = Get-Content $knownMktsPath -Raw | ConvertFrom-Json }
    catch { $km = [PSCustomObject]@{} }
} else {
    $km = [PSCustomObject]@{}
}

if (-not $km.PSObject.Properties[$marketplaceKey]) {
    $km | Add-Member -MemberType NoteProperty -Name $marketplaceKey -Value ([PSCustomObject]@{
        source = [PSCustomObject]@{ source = "github"; repo = $marketplaceRepo }
    })
    Write-Json $km $knownMktsPath
    Write-Host "Added to known_marketplaces.json" -ForegroundColor Green
} else {
    Write-Host "Already in known_marketplaces.json" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done! Restart Claude Desktop, then:" -ForegroundColor Green
Write-Host "  Settings -> Extensions -> Plugins -> Code -> install 'crisp-dev'" -ForegroundColor Cyan
Write-Host ""
Write-Host "Skills included:" -ForegroundColor Cyan
Write-Host "  /crisp-dev-csharp-style          - C# coding conventions for JDA/BlueYonder"
Write-Host "  /crisp-dev-jda-space-automation  - JDA Space Automation scripting"
Write-Host "  /crisp-dev-openaccess-controls   - OpenAccess custom control builder"
Write-Host "  /crisp-dev-datamanager-converter - Data Manager to OA control converter"
