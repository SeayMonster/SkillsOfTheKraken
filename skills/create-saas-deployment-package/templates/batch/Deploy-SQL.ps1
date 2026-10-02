# Deploy-SQL.ps1 - runs this package's SQL against CKB.
#
# On a batch server run it with no parameters: the connection comes from
# F:\batch\bin\set_env.ps1 (DBSOURCECKB, DBNAMECKB, DBUSER, DBPWD). Anywhere
# else pass -Server and -Database (integrated auth unless -User is given).
#
# Order: create the deploy log if missing, log Started, back up every object
# the package touches into Backup\<time>\, run SQL\*.sql in name order, log
# Succeeded or Failed. A failed backup stops before any SQL runs.
param(
    [string]$Server,
    [string]$Database,
    [string]$User,
    [string]$Password,
    [string]$SetEnv = 'F:\batch\bin\set_env.ps1'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'DeployLib.ps1')

if (-not $Server) {
    # set_env.ps1 is the vendor's script; dot-source it before strict mode.
    if (Test-Path $SetEnv) { . $SetEnv }
    $Server = $env:DBSOURCECKB; $Database = $env:DBNAMECKB; $User = $env:DBUSER; $Password = $env:DBPWD
}
Set-StrictMode -Version Latest
if (-not $Server -or -not $Database) {
    throw "No database connection: pass -Server and -Database, or run on a batch server that has $SetEnv."
}

$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
Write-Host "--- Release $($manifest.release) build $($manifest.build) -> $Database on $Server ---"

$conn = New-DeployConnection $Server $Database $User $Password
$key = $null
$current = 'cx_deploy_log.sql'
$done = 0
try {
    Invoke-DeploySql $conn ([IO.File]::ReadAllText((Join-Path $root 'cx_deploy_log.sql')))
    $backupDir = Join-Path $root ('Backup\' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    $key = Start-DeployLog $conn $manifest 'Deploy' $backupDir

    $current = 'backup'
    $entries = Backup-DeployObjects $conn $manifest $backupDir $key
    Copy-Item (Join-Path $root 'DeployLib.ps1'), (Join-Path $root 'Rollback.ps1') $backupDir
    Write-Host "  Backup: $(@($entries).Count) objects -> $backupDir"

    $files = @(Get-ChildItem (Join-Path $root 'SQL') -Filter '*.sql' | Sort-Object Name)
    foreach ($f in $files) {
        $current = $f.Name
        Write-Host "  [$($done + 1)/$($files.Count)] $($f.Name)"
        Invoke-DeploySql $conn ([IO.File]::ReadAllText($f.FullName))
        $done++
    }
    Complete-DeployLog $conn $key 'Succeeded' $null $done
    Write-Host "--- Deploy complete: $done files. To undo: $backupDir\Rollback.ps1 ---"
} catch {
    $msg = "$current : $($_.Exception.Message)"
    if ($key) { Complete-DeployLog $conn $key 'Failed' $msg $done }
    Write-Host "--- Deploy FAILED at $msg ---" -ForegroundColor Red
    throw
} finally {
    $conn.Close()
}
