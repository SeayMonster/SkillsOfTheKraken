# SkillsOfTheKraken - Claude Code Installer
# No prerequisites - uses only built-in PowerShell (Windows 10/11).
# Usage: paste into any PowerShell window:
#   irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/addclaudeskills.ps1 | iex

# Re-launch with execution-policy bypass if needed (fixes "not digitally signed" error)
if ($MyInvocation.ScriptName -and (Get-ExecutionPolicy) -in 'Restricted','AllSigned') {
    powershell -ExecutionPolicy Bypass -File $MyInvocation.ScriptName; exit
}

# UTF-8 BOM-safe write helper (avoids Claude Desktop JSON parse errors)
function Write-JsonNoBom($obj, $path) {
    $json = $obj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

# Strip BOM from a file if present (safety net for files manually edited in Notepad)
function Remove-Bom($path) {
    if (-not (Test-Path $path)) { return }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        [System.IO.File]::WriteAllBytes($path, $bytes[3..($bytes.Length - 1)])
    }
}

# Refresh PATH in-process after installs (avoids needing a new shell)
function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH    = "$machinePath;$userPath"
}

$repo       = "SeayMonster/SkillsOfTheKraken"
$branch     = "main"
$pluginName = "crisp-dev"
$pluginVer  = "1.0.0"
$marketKey  = "SkillsOfTheKraken"

$claudeDir      = "$env:USERPROFILE\.claude"
$settingsPath   = "$claudeDir\settings.json"
$marketplaceDir = "$claudeDir\plugins\marketplaces\$marketKey"
$cacheDir       = "$claudeDir\plugins\cache\$marketKey\$pluginName\$pluginVer\skills"

Write-Host ""
Write-Host "SkillsOfTheKraken Installer" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor DarkCyan
Write-Host ""

# Status tracking for summary
$statusNode      = ""
$statusClaude    = ""
$statusSuperpowers = ""
$statusKraken    = ""

# -----------------------------------------------------------------------
# Phase 0: Node.js
# -----------------------------------------------------------------------

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
    $nodeVer    = node --version 2>&1
    Write-Host "  [Node.js] $nodeVer already installed - skipped" -ForegroundColor Green
    $statusNode = "SKIPPED"
} else {
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "  ERROR: winget not found." -ForegroundColor Red
        Write-Host "         Install Node.js manually from https://nodejs.org (LTS), then re-run." -ForegroundColor Yellow
        Read-Host "Press Enter to close"
        exit 1
    }

    Write-Host "  [Node.js] Installing via winget..." -ForegroundColor Cyan
    winget install OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements
    Refresh-Path

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) {
        Write-Host "  ERROR: Node.js install failed." -ForegroundColor Red
        Write-Host "         Install manually from https://nodejs.org (LTS), then re-run." -ForegroundColor Yellow
        Read-Host "Press Enter to close"
        exit 1
    }

    $nodeVer    = node --version 2>&1
    Write-Host "  [Node.js] $nodeVer installed" -ForegroundColor Green
    $statusNode = "INSTALLED"
}

Write-Host ""

# -----------------------------------------------------------------------
# Phase 1: Claude CLI
# -----------------------------------------------------------------------

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    $claudeVer    = claude --version 2>&1
    Write-Host "  [Claude CLI] $claudeVer already installed - skipped" -ForegroundColor Green
    $statusClaude = "SKIPPED"
} else {
    Write-Host "  [Claude CLI] Installing via npm..." -ForegroundColor Cyan
    npm install -g @anthropic-ai/claude-code
    Refresh-Path

    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Write-Host "  ERROR: Claude CLI install failed." -ForegroundColor Red
        Write-Host "         Try manually: npm install -g @anthropic-ai/claude-code" -ForegroundColor Yellow
        Read-Host "Press Enter to close"
        exit 1
    }

    Write-Host "  [Claude CLI] Installed" -ForegroundColor Green
    $statusClaude = "INSTALLED"
}

# Activation check
$credsPath = "$env:USERPROFILE\.claude\.credentials.json"
if (Test-Path $credsPath) {
    Write-Host "  [Claude CLI] Already activated - skipped" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  ACTION REQUIRED: Log in to Claude." -ForegroundColor Yellow
    Write-Host "  A new terminal window will open running 'claude'." -ForegroundColor Yellow
    Write-Host "  Complete the login there, then come back to this window." -ForegroundColor Yellow
    Write-Host ""
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "claude"
    Read-Host "  Press Enter once you have logged in to Claude"

    if (Test-Path $credsPath) {
        Write-Host "  [Claude CLI] Activated" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Credentials not detected. Run 'claude' later to activate." -ForegroundColor Yellow
    }
}

Write-Host ""

# -----------------------------------------------------------------------
# Step 1: Git - check installed, or install GitHub Desktop
# -----------------------------------------------------------------------

function Get-GitHubDesktopGitPath {
    $ghDir = "$env:LOCALAPPDATA\GitHubDesktop"
    if (-not (Test-Path $ghDir)) { return $null }
    $appDir = Get-ChildItem $ghDir -Directory -Filter "app-*" -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending | Select-Object -First 1
    if (-not $appDir) { return $null }
    $gitCmd = "$($appDir.FullName)\resources\app\git\cmd"
    if (Test-Path "$gitCmd\git.exe") { return $gitCmd }
    return $null
}

function Add-ToUserPath([string]$newPath) {
    $current = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($current -notlike "*$newPath*") {
        [Environment]::SetEnvironmentVariable("PATH", "$current;$newPath", "User")
        $env:PATH = "$env:PATH;$newPath"
    }
}

$gitOk = [bool](Get-Command git -ErrorAction SilentlyContinue)

if (-not $gitOk) {
    # Git not in PATH - check if GitHub Desktop is already installed
    $ghGit = Get-GitHubDesktopGitPath
    if ($ghGit) {
        Add-ToUserPath $ghGit
        $gitOk = $true
        Write-Host "  [1/4] Git found via GitHub Desktop - added to PATH" -ForegroundColor Green
    }
}

if (-not $gitOk) {
    Write-Host "  [1/4] Git not found - downloading GitHub Desktop..." -ForegroundColor Cyan

    $setup = "$env:TEMP\GitHubDesktopSetup.exe"
    try {
        Invoke-WebRequest -Uri "https://central.github.com/deployments/desktop/desktopapp/latest/win32" `
                          -OutFile $setup -UseBasicParsing
    } catch {
        Write-Host "  ERROR: Could not download GitHub Desktop. Check your internet connection." -ForegroundColor Red
        exit 1
    }

    # Squirrel installer - launches, forks, exits; actual install runs in background
    Start-Process -FilePath $setup -ErrorAction SilentlyContinue
    Remove-Item $setup -Force -ErrorAction SilentlyContinue

    Write-Host "  Installing GitHub Desktop (this may take a minute)..." -ForegroundColor DarkCyan
    $waited = 0
    $ghGit  = $null
    while ($waited -lt 90) {
        Start-Sleep -Seconds 3
        $waited += 3
        $ghGit = Get-GitHubDesktopGitPath
        if ($ghGit) { break }
    }

    if ($ghGit) {
        Add-ToUserPath $ghGit
        Write-Host "  [1/4] GitHub Desktop installed - git is ready" -ForegroundColor Green
        Write-Host ""
        Write-Host "  ACTION REQUIRED: Open GitHub Desktop and sign in to your GitHub account." -ForegroundColor Yellow
        Write-Host "  Claude Code will handle all commits and pushes - you just need to be signed in." -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "  [1/4] GitHub Desktop installed but git path not detected yet." -ForegroundColor Yellow
        Write-Host "         Re-run this installer after GitHub Desktop finishes loading." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [1/4] Git already installed - skipped" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# Step 2: Register marketplace in settings.json
# -----------------------------------------------------------------------

if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir | Out-Null }

Remove-Bom $settingsPath

if (Test-Path $settingsPath) {
    $raw = Get-Content $settingsPath -Raw
    try   { $settings = $raw | ConvertFrom-Json }
    catch {
        Write-Host "  ERROR: $settingsPath contains invalid JSON. Fix it manually first." -ForegroundColor Red
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
    Write-JsonNoBom $settings $settingsPath
    Write-Host "  [2/4] Marketplace registered in settings.json" -ForegroundColor Green
} else {
    Write-Host "  [2/4] Marketplace already registered - skipped" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# Step 3: Download repo ZIP and copy to marketplace dir
# -----------------------------------------------------------------------

$zipUrl = "https://github.com/$repo/archive/refs/heads/$branch.zip"
$tmpZip = "$env:TEMP\SkillsOfTheKraken-$branch.zip"
$tmpDir = "$env:TEMP\SkillsOfTheKraken-extract"
$srcDir = "$tmpDir\$($repo.Split('/')[-1])-$branch"

Write-Host "  [3/4] Downloading skills from GitHub..." -ForegroundColor Cyan

try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing
} catch {
    Write-Host "  ERROR: Could not download skills. Check your internet connection." -ForegroundColor Red
    exit 1
}

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
Remove-Item $tmpZip -Force

if (Test-Path $marketplaceDir) { Remove-Item $marketplaceDir -Recurse -Force }
Copy-Item $srcDir $marketplaceDir -Recurse -Force
Remove-Item $tmpDir -Recurse -Force

Write-Host "  [3/4] Skills downloaded" -ForegroundColor Green

# -----------------------------------------------------------------------
# Step 4: Populate plugin cache (no /plugin install needed)
# -----------------------------------------------------------------------

# Wipe cache clean first to remove any stale/renamed skills from previous installs
if (Test-Path $cacheDir) { Remove-Item $cacheDir -Recurse -Force }
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

Get-ChildItem "$marketplaceDir\skills" -Directory | ForEach-Object {
    Copy-Item $_.FullName "$cacheDir\$($_.Name)" -Recurse -Force
}

Write-Host "  [4/5] Plugin cache populated" -ForegroundColor Green

# -----------------------------------------------------------------------
# Step 5: Register plugin in installed_plugins.json
# -----------------------------------------------------------------------

$installedPluginsPath = "$claudeDir\plugins\installed_plugins.json"
$pluginKey            = "$pluginName@$marketKey"
$installPath          = "$claudeDir\plugins\cache\$marketKey\$pluginName\$pluginVer"
$now                  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

Remove-Bom $installedPluginsPath

if (Test-Path $installedPluginsPath) {
    try   { $ip = Get-Content $installedPluginsPath -Raw | ConvertFrom-Json }
    catch { $ip = [PSCustomObject]@{ version = 2; plugins = [PSCustomObject]@{} } }
} else {
    $ip = [PSCustomObject]@{ version = 2; plugins = [PSCustomObject]@{} }
}

if (-not $ip.PSObject.Properties["plugins"]) {
    $ip | Add-Member -MemberType NoteProperty -Name "plugins" -Value ([PSCustomObject]@{})
}

$entry = @([PSCustomObject]@{
    scope       = "user"
    installPath = $installPath
    version     = $pluginVer
    installedAt = $now
    lastUpdated = $now
})

if ($ip.plugins.PSObject.Properties[$pluginKey]) {
    $ip.plugins.PSObject.Properties.Remove($pluginKey)
}
$ip.plugins | Add-Member -MemberType NoteProperty -Name $pluginKey -Value $entry

New-Item -ItemType Directory -Path (Split-Path $installedPluginsPath) -Force | Out-Null
Write-JsonNoBom $ip $installedPluginsPath

# -----------------------------------------------------------------------
# Step 6: Enable plugin in settings.json
# -----------------------------------------------------------------------

Remove-Bom $settingsPath
$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

if (-not $settings.PSObject.Properties["enabledPlugins"]) {
    $settings | Add-Member -MemberType NoteProperty -Name "enabledPlugins" -Value ([PSCustomObject]@{})
}
if (-not $settings.enabledPlugins.PSObject.Properties[$pluginKey]) {
    $settings.enabledPlugins | Add-Member -MemberType NoteProperty -Name $pluginKey -Value $true
    Write-JsonNoBom $settings $settingsPath
}

Write-Host "  [5/5] Plugin registered and enabled" -ForegroundColor Green

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------

Write-Host ""
Write-Host "All done! Restart Claude Code and the skills will be ready." -ForegroundColor Green
Write-Host ""
Write-Host "Skills installed:" -ForegroundColor Cyan
Get-ChildItem $cacheDir -Directory | ForEach-Object {
    Write-Host "  /$($_.Name)"
}
Write-Host ""
