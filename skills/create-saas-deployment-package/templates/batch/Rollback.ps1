# Rollback.ps1 - undoes the deploy whose backup folder this is.
#
# Deploy-SQL.ps1 copies this file and DeployLib.ps1 into Backup\<time>\.
# Same connection rules as Deploy-SQL.ps1. Refuses when a later deploy that
# was not itself rolled back changed any of the same objects -- roll that one
# back first (newest build first), or pass -Force. Tables and table types are
# reference only and are not restored.
param(
    [string]$Server,
    [string]$Database,
    [string]$User,
    [string]$Password,
    [string]$SetEnv = 'F:\batch\bin\set_env.ps1',
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'DeployLib.ps1')

if (-not $Server) {
    if (Test-Path $SetEnv) { . $SetEnv }
    $Server = $env:DBSOURCECKB; $Database = $env:DBNAMECKB; $User = $env:DBUSER; $Password = $env:DBPWD
}
Set-StrictMode -Version Latest
if (-not $Server -or -not $Database) {
    throw "No database connection: pass -Server and -Database, or run on a batch server that has $SetEnv."
}

$bm = Get-Content (Join-Path $root 'backup-manifest.json') -Raw | ConvertFrom-Json
$names = @(@($bm.objects) | ForEach-Object { [string]$_.name })
Write-Host "--- Rollback release $($bm.release) build $($bm.build) on $Database ($Server) ---"

$conn = New-DeployConnection $Server $Database $User $Password
$key = $null
$current = 'overlap check'
try {
    $later = Get-DeployRows $conn @'
SELECT TOP 1 l.dbkey, l.Release, l.Build
FROM ckbcustom.cx_deploy_log l
WHERE l.dbkey > @Key
  AND l.Action = 'Deploy' AND l.Result = 'Succeeded'
  AND NOT EXISTS (SELECT 1 FROM ckbcustom.cx_deploy_log r
                  WHERE r.Action = 'Rollback' AND r.Result = 'Succeeded' AND r.RolledBackKey = l.dbkey)
  AND EXISTS (SELECT 1 FROM OPENJSON(l.Objects) a JOIN OPENJSON(@Objects) b ON a.value = b.value)
ORDER BY l.dbkey
'@ @{ Key = [int]$bm.logKey; Objects = (ConvertTo-Json -InputObject $names -Compress) }
    if ($later.Rows.Count -gt 0 -and -not $Force) {
        $r = $later.Rows[0]
        throw "Release $($r.Release) build $($r.Build) (log $($r.dbkey)) changed the same objects after this deploy - roll that back first, or pass -Force."
    }

    $logManifest = [PSCustomObject]@{ release = $bm.release; build = $bm.build; tag = $bm.tag; commit = $null; objects = $bm.objects }
    $key = Start-DeployLog $conn $logManifest 'Rollback' $root ([int]$bm.logKey)

    $current = '00_rollback_drops.sql'
    Invoke-DeploySql $conn ([IO.File]::ReadAllText((Join-Path $root '00_rollback_drops.sql')))
    $done = 1
    foreach ($o in @(@($bm.objects) | Where-Object { $_.state -eq 'existed' })) {
        $f = Join-Path $root ((Get-SafeFileName $o.name) + '.sql')
        $current = Split-Path $f -Leaf
        Write-Host "  restore $($o.name)"
        Invoke-DeploySql $conn ([IO.File]::ReadAllText($f))
        $done++
    }
    Complete-DeployLog $conn $key 'Succeeded' $null $done
    $refs = @(@($bm.objects) | Where-Object { $_.state -eq 'reference' } | ForEach-Object { $_.name })
    if ($refs.Count -gt 0) { Write-Host "  Not restored (reference only): $($refs -join ', ')" }
    Write-Host '--- Rollback complete ---'
} catch {
    $msg = "$current : $($_.Exception.Message)"
    if ($key) { Complete-DeployLog $conn $key 'Failed' $msg }
    Write-Host "--- Rollback FAILED at $msg ---" -ForegroundColor Red
    throw
} finally {
    $conn.Close()
}
