# SkillsOfTheKraken - Claude Code Installer
# No prerequisites — uses only built-in PowerShell (Windows 10/11).
# Usage: paste into any PowerShell window:
#   irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/addclaudeskills.ps1 | iex

$repo        = "SeayMonster/SkillsOfTheKraken"
$branch      = "main"
$pluginName  = "crisp-dev"
$pluginVer   = "1.0.0"
$marketKey   = "SkillsOfTheKraken"

$claudeDir      = "$env:USERPROFILE\.claude"
$settingsPath   = "$claudeDir\settings.json"
$marketplaceDir = "$claudeDir\plugins\marketplaces\$marketKey"
$cacheDir       = "$claudeDir\plugins\cache\$marketKey\$pluginName\$pluginVer\skills"

Write-Host ""
Write-Host "Installing SkillsOfTheKraken..." -ForegroundColor Cyan

# --- Step 1: settings.json marketplace entry ---

if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir | Out-Null
}

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

$alreadyRegistered = $settings.PSObject.Properties["extraKnownMarketplaces"] -and
                     $settings.extraKnownMarketplaces.PSObject.Properties[$marketKey]

if (-not $alreadyRegistered) {
    if (-not $settings.PSObject.Properties["extraKnownMarketplaces"]) {
        $settings | Add-Member -MemberType NoteProperty -Name "extraKnownMarketplaces" -Value ([PSCustomObject]@{})
    }
    $entry = [PSCustomObject]@{
        source = [PSCustomObject]@{ source = "github"; repo = $repo }
    }
    $settings.extraKnownMarketplaces | Add-Member -MemberType NoteProperty -Name $marketKey -Value $entry
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8
    Write-Host "  [1/3] Marketplace registered in settings.json" -ForegroundColor Green
} else {
    Write-Host "  [1/3] Marketplace already registered — skipped" -ForegroundColor Yellow
}

# --- Step 2: Download repo ZIP and extract to marketplace dir ---

$zipUrl  = "https://github.com/$repo/archive/refs/heads/$branch.zip"
$tmpZip  = "$env:TEMP\SkillsOfTheKraken-$branch.zip"
$tmpDir  = "$env:TEMP\SkillsOfTheKraken-extract"
$srcDir  = "$tmpDir\$($repo.Split('/')[-1])-$branch"

Write-Host "  [2/3] Downloading skills from GitHub..." -ForegroundColor Cyan

try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing
} catch {
    Write-Host "ERROR: Could not download from GitHub. Check your internet connection." -ForegroundColor Red
    exit 1
}

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
Remove-Item $tmpZip -Force

# Copy to marketplace dir (replaces existing)
if (Test-Path $marketplaceDir) { Remove-Item $marketplaceDir -Recurse -Force }
Copy-Item $srcDir $marketplaceDir -Recurse -Force
Remove-Item $tmpDir -Recurse -Force

Write-Host "  [2/3] Skills downloaded to marketplace directory" -ForegroundColor Green

# --- Step 3: Populate plugin cache so skills load without /plugin install ---

if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}

$skillsSrc = "$marketplaceDir\skills"
Get-ChildItem $skillsSrc -Directory | ForEach-Object {
    $dest = "$cacheDir\$($_.Name)"
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $_.FullName $dest -Recurse -Force
}

Write-Host "  [3/3] Plugin cache populated" -ForegroundColor Green

# --- Done ---

Write-Host ""
Write-Host "Done! Restart Claude Code and the skills will be ready." -ForegroundColor Green
Write-Host ""
Write-Host "Skills available:" -ForegroundColor Cyan
Write-Host "  /crisp-dev-csharp-style          - C# coding conventions for JDA/BlueYonder"
Write-Host "  /crisp-dev-jda-space-automation  - JDA Space Automation scripting"
Write-Host "  /crisp-dev-openaccess-controls   - OpenAccess custom control builder"
Write-Host "  /crisp-dev-datamanager-converter - Data Manager to OA control converter"
Write-Host "  /crisp-dev-generate-deployment   - Generate SQL deployment package (--saas / --direct)"
Write-Host "  /crisp-dev-spec-reviewer         - Generate interactive HTML spec review pages"
Write-Host "  /crisp-dev-switch-sql-mcp        - Repoint mssql MCP between local/client connections"
Write-Host "  /crisp-dev-register-skill-repo   - Register any GitHub skill repo"
Write-Host ""
Write-Host "No restart needed if you just updated — run /skills in Claude Code to reload." -ForegroundColor DarkCyan
