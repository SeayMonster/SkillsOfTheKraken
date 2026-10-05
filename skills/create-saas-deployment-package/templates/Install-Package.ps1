# Install-Package.ps1 - installs one deployment package build on the batch server.
#
# HOW TO RUN
#   1. Copy the whole build folder to the server (e.g. S:\_Deploy\2026-10-05\01_1012).
#   2. Open PowerShell, go to that folder and run:
#        powershell -ExecutionPolicy Bypass -File .\Install-Package.ps1
#   An elevated (Run as Administrator) window may not see mapped drives such
#   as S:. Run it normally first; use an elevated window only if a copy step
#   reports "access denied".
#
# WHAT IT DOES, IN ORDER
#   Each step runs only when its zip is in this folder. The first failure stops
#   everything, so nothing later runs against a half-installed package.
#   1. Unzip   - every deploy-*.zip into a subfolder of this folder (batch\,
#                sapro\, web\) and unblock the files, so PowerShell will run
#                scripts that were copied from another machine.
#   2. SQL     - batch\Deploy-SQL.ps1. Logs the run to ckbcustom.cx_deploy_log,
#                backs up every object it changes into batch\Backup\<time>\,
#                then runs the SQL. The connection comes from this server's
#                F:\batch\bin\set_env.ps1 (set_db.ps1); the package holds none.
#   3. EXE     - batch\Deploy-Exe.ps1, only if the package has console apps.
#   4. SA Pro  - sapro\Deploy-SaPro.ps1, only if the package has SA Pro scripts.
#   5. Web     - web\Deploy-Web.ps1, only if the package has web files.
#
# OPTIONS
#   -SkipSql -SkipExe -SkipSaPro -SkipWeb   leave a step out.
#   Re-running is safe: the SQL is rerunnable and earlier backups are kept.
#
# UNDO
#   SQL: run batch\Backup\<time>\Rollback.ps1. Roll back the newest build first;
#   it refuses if a later build changed the same objects. Tables are not restored.
param(
    [switch]$SkipSql,
    [switch]$SkipExe,
    [switch]$SkipSaPro,
    [switch]$SkipWeb
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Helpers ---

function Write-Step([string]$text) {
    Write-Host ''
    Write-Host "=== $text ===" -ForegroundColor Cyan
}

# Each package script runs in its own PowerShell: its environment (set_env.ps1)
# stays out of this one, and its exit code decides whether the install goes on.
function Invoke-PackageScript([string]$path) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $path
    if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $path -Leaf) failed (exit code $LASTEXITCODE)" }
}

try {
    Write-Host "Installing package in $root"

    # --- 1. Unzip ---
    # -Force refreshes the package files on a re-run. Backup\ is not in any zip,
    # so backups from earlier runs are left where they are.
    $parts = [ordered]@{ batch = 'deploy-batch.zip'; sapro = 'deploy-sapro.zip'; web = 'deploy-web.zip' }
    foreach ($name in $parts.Keys) {
        $zip = Join-Path $root $parts[$name]
        if (-not (Test-Path $zip)) { continue }
        $dest = Join-Path $root $name
        Write-Step "1. Unzip $($parts[$name]) -> $name\"
        Expand-Archive -Path $zip -DestinationPath $dest -Force
        Get-ChildItem $dest -Recurse -File | Unblock-File
    }

    # --- 2. SQL ---
    $sql = Join-Path $root 'batch\Deploy-SQL.ps1'
    if ($SkipSql) { Write-Step '2. SQL - skipped (-SkipSql)' }
    elseif (Test-Path $sql) { Write-Step '2. SQL'; Invoke-PackageScript $sql }

    # --- 3. EXE (console apps) ---
    $exe = Join-Path $root 'batch\Deploy-Exe.ps1'
    if ($SkipExe) { Write-Step '3. EXE - skipped (-SkipExe)' }
    elseif (Test-Path $exe) { Write-Step '3. EXE'; Invoke-PackageScript $exe }

    # --- 4. SA Pro scripts ---
    $sapro = Join-Path $root 'sapro\Deploy-SaPro.ps1'
    if ($SkipSaPro) { Write-Step '4. SA Pro - skipped (-SkipSaPro)' }
    elseif (Test-Path $sapro) { Write-Step '4. SA Pro'; Invoke-PackageScript $sapro }
    elseif (Test-Path (Join-Path $root 'sapro')) {
        # No location in client.json: the README in sapro\ says where they go.
        Write-Step '4. SA Pro - no Deploy-SaPro.ps1; copy sapro\*.dll by hand (see sapro\README-SAPRO.md)'
    }

    # --- 5. Web ---
    # Only when the web zip actually carries files; a package with no web
    # projects still ships an empty one.
    $web = Join-Path $root 'web\Deploy-Web.ps1'
    $webFiles = @(Get-ChildItem (Join-Path $root 'web\WebFiles') -Recurse -File -ErrorAction SilentlyContinue)
    if ($SkipWeb) { Write-Step '5. Web - skipped (-SkipWeb)' }
    elseif ((Test-Path $web) -and $webFiles.Count -gt 0) { Write-Step '5. Web'; Invoke-PackageScript $web }

    # --- Done ---
    Write-Step 'Package installed'
    $backup = Get-ChildItem (Join-Path $root 'batch\Backup') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -Last 1
    if ($backup) { Write-Host "To undo the SQL: $(Join-Path $backup.FullName 'Rollback.ps1')" }
    exit 0
} catch {
    Write-Host ''
    Write-Host "=== INSTALL FAILED: $($_.Exception.Message) ===" -ForegroundColor Red
    Write-Host 'Nothing after the failed step ran. Fix the cause and run Install-Package.ps1 again.'
    exit 1
}
