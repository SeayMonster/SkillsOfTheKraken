# SkillsOfTheKraken - Claude Code Installer
# Usage: paste into any PowerShell window:
#   irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/install.ps1 | iex

if ($MyInvocation.ScriptName -and (Get-ExecutionPolicy) -in 'Restricted','AllSigned') {
    powershell -ExecutionPolicy Bypass -File $MyInvocation.ScriptName; exit
}

function Write-JsonNoBom($obj, $path) {
    $json = $obj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}
function Remove-Bom($path) {
    if (-not (Test-Path $path)) { return }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        [System.IO.File]::WriteAllBytes($path, $bytes[3..($bytes.Length - 1)])
    }
}

$repo       = "SeayMonster/SkillsOfTheKraken"
$branch     = "main"
$pluginName = "kraken"
$pluginVer  = "1.0.0"
$marketKey  = "SeayMonster"

$claudeDir    = "$env:USERPROFILE\.claude"
$settingsPath = "$claudeDir\settings.json"
$cacheRoot    = "$claudeDir\plugins\cache"
$cacheDir     = "$cacheRoot\$marketKey\$pluginName\$pluginVer\skills"

Write-Host ""
Write-Host "SkillsOfTheKraken Installer" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor DarkCyan
Write-Host ""

$zipUrl = "https://github.com/$repo/archive/refs/heads/$branch.zip"
$tmpZip = "$env:TEMP\kraken.zip"
$tmpDir = "$env:TEMP\kraken-extract"

Write-Host "Downloading..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
$extractedDir = (Get-ChildItem $tmpDir -Directory | Select-Object -First 1).FullName

New-Item -ItemType Directory -Force "$cacheRoot\$marketKey\$pluginName\$pluginVer" | Out-Null
New-Item -ItemType Directory -Force $cacheDir | Out-Null
Copy-Item "$extractedDir\skills\*" $cacheDir -Recurse -Force
Copy-Item "$extractedDir\.claude-plugin\*" "$cacheRoot\$marketKey\$pluginName\$pluginVer" -Recurse -Force
$count = (Get-ChildItem $cacheDir -Directory).Count
Write-Host "  $count skills cached." -ForegroundColor Green

New-Item -ItemType Directory -Force $claudeDir | Out-Null
Remove-Bom $settingsPath
$settings = if (Test-Path $settingsPath) { try { Get-Content $settingsPath -Raw | ConvertFrom-Json } catch { [PSCustomObject]@{} } } else { [PSCustomObject]@{} }

if (-not $settings.PSObject.Properties['enabledPlugins']) {
    $settings | Add-Member -NotePropertyName 'enabledPlugins' -NotePropertyValue ([PSCustomObject]@{})
}
$settings.enabledPlugins | Add-Member -NotePropertyName "$pluginName@$marketKey" -NotePropertyValue $true -Force

if (-not $settings.PSObject.Properties['extraKnownMarketplaces']) {
    $settings | Add-Member -NotePropertyName 'extraKnownMarketplaces' -NotePropertyValue ([PSCustomObject]@{})
}
$settings.extraKnownMarketplaces | Add-Member -NotePropertyName $marketKey -NotePropertyValue ([PSCustomObject]@{
    source = [PSCustomObject]@{ source = "github"; repo = $repo }
    autoUpdate = $true
}) -Force

Write-JsonNoBom $settings $settingsPath

Remove-Item $tmpZip, $tmpDir -Recurse -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done. Restart Claude Code." -ForegroundColor Green
Write-Host ""
Write-Host "Skills (kraken):" -ForegroundColor Cyan
Get-ChildItem $cacheDir -Directory | ForEach-Object { Write-Host "  kraken:$($_.Name)" }
Write-Host ""