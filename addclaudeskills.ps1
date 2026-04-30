# SkillsOfTheKraken - Claude Code Installer
# Run this once to add the skill marketplace to your Claude Code settings.
# Usage: Right-click -> "Run with PowerShell"  OR  paste into a terminal: irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/install.ps1 | iex

$settingsPath = "$env:USERPROFILE\.claude\settings.json"
$marketplaceKey = "SkillsOfTheKraken"
$marketplaceEntry = @{
    source = @{
        source = "github"
        repo   = "SeayMonster/SkillsOfTheKraken"
    }
}

# Ensure .claude directory exists
$claudeDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir | Out-Null
}

# Load or create settings.json
if (Test-Path $settingsPath) {
    $raw = Get-Content $settingsPath -Raw
    try {
        $settings = $raw | ConvertFrom-Json
    } catch {
        Write-Host "ERROR: $settingsPath contains invalid JSON. Fix it manually first." -ForegroundColor Red
        exit 1
    }
} else {
    $settings = [PSCustomObject]@{}
}

# Check if already installed
if ($settings.PSObject.Properties["extraKnownMarketplaces"] -and
    $settings.extraKnownMarketplaces.PSObject.Properties[$marketplaceKey]) {
    Write-Host "SkillsOfTheKraken is already installed. Nothing to do." -ForegroundColor Yellow
    exit 0
}

# Add extraKnownMarketplaces if missing
if (-not $settings.PSObject.Properties["extraKnownMarketplaces"]) {
    $settings | Add-Member -MemberType NoteProperty -Name "extraKnownMarketplaces" -Value ([PSCustomObject]@{})
}

# Add the marketplace entry
$settings.extraKnownMarketplaces | Add-Member -MemberType NoteProperty -Name $marketplaceKey -Value $marketplaceEntry

# Write back
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8

Write-Host ""
Write-Host "Done! SkillsOfTheKraken skills are now available in Claude Code." -ForegroundColor Green
Write-Host ""
Write-Host "Skills installed:" -ForegroundColor Cyan
Write-Host "  /crisp-dev-csharp-style          - C# coding conventions for JDA/BlueYonder"
Write-Host "  /crisp-dev-jda-space-automation  - JDA Space Automation scripting"
Write-Host "  /crisp-dev-openaccess-controls   - OpenAccess custom control builder"
Write-Host "  /crisp-dev-datamanager-converter - Data Manager to OA control converter"
Write-Host ""
Write-Host "Restart Claude Code or run /skills to reload." -ForegroundColor Cyan
