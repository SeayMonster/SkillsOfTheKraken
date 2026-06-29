#Requires -Version 5.1
<#
.SYNOPSIS
  kraken-cursor: build SaaS deployment package (full SQL install + diff-aware README).
.PARAMETER RepoRoot
  Client repo root (contains _package-request.json).
.PARAMETER Flag
  --saas (default) or --local
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [string]$Flag = '--saas'
)

$ErrorActionPreference = 'Stop'
Set-Location $RepoRoot

function Get-Tier([string]$path) {
    $leaf = Split-Path $path -Leaf
    if ($path -match '[\\/]Tables[\\/]' -and $leaf -notmatch '^Populate') { return 1 }
    if ($leaf -match '^Populate|^ckbcustom\.Populate') { return 2 }
    if ($path -match '[\\/]Functions[\\/]') { return 3 }
    if ($path -match '[\\/]Views[\\/]') { return 4 }
    if ($path -match '[\\/]Stored Procedures[\\/]|[\\/]Store Procedures[\\/]|[\\/]Procedures[\\/]') { return 5 }
    return 99
}

function Get-ObjectName([string]$path) {
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    if ($name -match '^ckbcustom\.') { return $name.ToLower() }
    if ($path -match '[\\/]Configuration[\\/]') { return $name.ToLower() }
    return "ckbcustom.$name".ToLower()
}

function Get-ObjectType([int]$tier) {
    switch ($tier) {
        1 { 'Table' }
        2 { 'Data' }
        3 { 'Function' }
        4 { 'View' }
        5 { 'Stored Procedure' }
        default { 'Unknown' }
    }
}

function Get-TierSection([int]$tier) {
    switch ($tier) {
        1 { 'TABLES' }
        2 { 'DATA' }
        3 { 'FUNCTIONS' }
        4 { 'VIEWS' }
        5 { 'STORED PROCEDURES' }
        default { 'UNKNOWN' }
    }
}

function Clean-SqlContent([string]$content) {
    $lines = $content -split "`r?`n"
    if ($lines.Count -gt 0) { $lines[0] = $lines[0].TrimStart([char]0xFEFF) }
    $text = ($lines -join "`r`n").Trim()
    $text = [regex]::Replace($text, '(?is)^\s*USE\s+\[?\w+\]?\s*\r?\nGO\s*\r?\n', '')
    while ($text -match '(?is)^\s*GO\s*(\r?\n|$)') { $text = [regex]::Replace($text, '(?is)^\s*GO\s*(\r?\n|$)', '', 1) }
    while ($text -match '(?is)(\r?\n|^)\s*GO\s*$') { $text = [regex]::Replace($text, '(?is)(\r?\n|^)\s*GO\s*$', '', 1) }
    return $text.Trim()
}

function Extract-Grants([string]$content) {
    $grants = [regex]::Matches($content, '(?im)^GRANT\s+.+?;\s*$') | ForEach-Object { $_.Value.Trim() }
    $body = [regex]::Replace($content, '(?im)^GRANT\s+.+?;\s*\r?\n?', '')
    return @{ Body = $body.Trim(); Grants = $grants }
}

function Get-AllSqlFiles([string]$projectName) {
    $root = Join-Path $RepoRoot $projectName
    $sqlRoot = Join-Path $root 'SQL'
    if (-not (Test-Path $sqlRoot)) { return @() }
    Get-ChildItem $sqlRoot -Recurse -Filter '*.sql' -File |
        Where-Object {
            $_.FullName -notmatch '\\Tests\\|\\Old procs\\|\\\.vs\\|\\.git\\'
        } |
        Where-Object { $_.Length -gt 0 } |
        ForEach-Object {
            $rel = $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
            [PSCustomObject]@{ path = $rel; tier = (Get-Tier $rel); project = $projectName }
        }
}

function Get-ChangedFiles([string]$projectName, [string]$baseline) {
    $files = @()
    git diff --name-only $baseline HEAD -- "$projectName/" 2>$null | ForEach-Object { $files += $_ }
    git diff --name-only $baseline -- "$projectName/" 2>$null | ForEach-Object { if ($files -notcontains $_) { $files += $_ } }
    $files | Where-Object {
        $_ -and $_ -notmatch '\.(md|csproj|sqlproj|sln|json|ps1|html)$' `
            -and $_ -notmatch 'Tests/|Old procs/|Deployments/|docs/|\.claude/'
    }
}

# --- Read request ---
$requestPath = Join-Path $RepoRoot '_package-request.json'
if (-not (Test-Path $requestPath)) { throw "_package-request.json not found in $RepoRoot" }
$request = Get-Content $requestPath -Raw | ConvertFrom-Json
if (-not $request.projects -or $request.projects.Count -eq 0) { throw 'No projects in _package-request.json' }
if (-not $request.environment) { throw 'environment is required in _package-request.json' }

$envConfigPath = Join-Path $RepoRoot 'Environment Details\env-config.json'
if (-not (Test-Path $envConfigPath)) { throw "env-config.json not found" }
$envConfig = Get-Content $envConfigPath -Raw | ConvertFrom-Json
$envEntry = $envConfig.($request.environment)
if (-not $envEntry) { throw "env-config.json has no entry for '$($request.environment)'" }

$server = $envEntry.Server
$database = $envEntry.Database
$baseline = $request.baseline
if (-not $baseline) {
    $baseline = git tag --list "deploy/$($request.environment)/*" --sort=-version:refname | Select-Object -First 1
    if (-not $baseline) { throw "No deploy tag found for $($request.environment). Set baseline in _package-request.json." }
}

$deployDate = Get-Date -Format 'yyyy-MM-dd'
$deployDir = Join-Path $RepoRoot "Deployments\$deployDate"
$webTarget = if ($request.webTarget) { $request.webTarget } else { 'U:\OpenAccess\Customization\' }
$batchTarget = if ($request.batchTarget) { $request.batchTarget } else { 'F:\batch\exe' }
$commitMessages = @(git log "$baseline..HEAD" --pretty='%s' 2>$null)

New-Item -ItemType Directory -Path $deployDir -Force | Out-Null

# --- Gather: ALL SQL (full install) + diffs for README ---
$projectData = @()
$allSql = @()
$seenObjects = @{}

foreach ($proj in $request.projects) {
    $sqlFiles = @(Get-AllSqlFiles $proj | Sort-Object tier, path)
    $changed = @(Get-ChangedFiles $proj $baseline)
    $changedSql = $changed | Where-Object { $_ -match '\.sql$' }
    $changedCs  = $changed | Where-Object { $_ -match '\.cs$' }

    foreach ($s in $sqlFiles) {
        $key = Get-ObjectName $s.path
        if (-not $seenObjects.ContainsKey($key)) {
            $seenObjects[$key] = $true
            $allSql += $s
        }
    }

    $projectData += [PSCustomObject]@{
        projectName  = $proj
        projectRoot  = "$proj/"
        sqlFiles     = $sqlFiles
        csFiles      = @($changedCs | ForEach-Object { [PSCustomObject]@{ path = $_ } })
        changedFiles = $changed
        changedSql   = $changedSql
        changedCs    = $changedCs
        hasSql       = ($sqlFiles.Count -gt 0)
        hasChanges   = ($changed.Count -gt 0)
    }
}

if ($allSql.Count -eq 0) { throw 'No SQL files found for selected projects.' }

# --- Build deploy.sql ---
$objects = @()
$allGrants = [System.Collections.Generic.List[string]]::new()
$tierBodies = @{ 1 = @(); 2 = @(); 3 = @(); 4 = @(); 5 = @(); 99 = @() }
$num = 1

foreach ($item in ($allSql | Sort-Object tier, path)) {
    $fullPath = Join-Path $RepoRoot ($item.path -replace '/', '\')
    $raw = Get-Content -Raw -LiteralPath $fullPath
    $clean = Clean-SqlContent $raw
    $parsed = Extract-Grants $clean
    foreach ($g in $parsed.Grants) { if ($allGrants -notcontains $g) { [void]$allGrants.Add($g) } }

    $note = ($raw -split "`r?`n" | Where-Object {
        $_ -match '^\s*--' -and $_ -notmatch 'Development\s*:|Author\s*:|Date\s*:|Version|M O D I F I C A T I O N S|I N I T I A L|='
    } | Select-Object -First 1)
    if ($note) { $note = ($note -replace '^\s*--\s*', '').Trim() }
    if (-not $note) { $note = (git log -1 --pretty=%s -- $item.path 2>$null) }
    if (-not $note) { $note = $item.project }

    $displayName = Get-ObjectName $item.path
    if ($displayName -notmatch '^ckbcustom\.' -and $item.path -match 'Configuration') {
        $displayName = [IO.Path]::GetFileNameWithoutExtension($item.path)
    } elseif ($displayName -match '^ckbcustom\.') {
        $displayName = 'ckbcustom.' + ($displayName -replace '^ckbcustom\.', '')
    }

    $objects += [PSCustomObject]@{
        Number = $num
        Name   = $displayName
        Type   = (Get-ObjectType $item.tier)
        Notes  = $note
        Tier   = $item.tier
        Path   = $item.path
        Project = $item.project
    }
    $tierBodies[$item.tier] += $parsed.Body
    $num++
}

$header = @"
-- ============================================================
-- Deployment: $deployDate
-- Target:     $server  |  Database: $database
-- Run in:     SSMS -- safe to re-run (all CREATE OR ALTER)
-- Mode:       Full SQL install for: $($request.projects -join ', ')
-- ============================================================
"@
foreach ($o in $objects) {
    $header += "`n-- $($o.Number). $($o.Name)   $($o.Type)   $($o.Notes)"
}
$header += "`n-- ============================================================`n`nUSE $database`nGO`n"

$deploySql = $header
foreach ($tier in 1, 2, 3, 4, 5) {
    if ($tierBodies[$tier].Count -eq 0) { continue }
    $deploySql += "`n-- --------------------------------------------------------`n-- $(Get-TierSection $tier)`n-- --------------------------------------------------------`n"
    $deploySql += ($tierBodies[$tier] -join "`nGO`n`n") + "`nGO`n"
}
if ($tierBodies[99].Count -gt 0) {
    $deploySql += "`n-- --------------------------------------------------------`n-- UNKNOWN (verify ordering manually)`n-- --------------------------------------------------------`n"
    $deploySql += ($tierBodies[99] -join "`nGO`n`n") + "`nGO`n"
}
if ($allGrants.Count -gt 0) {
    $deploySql += "`n-- --------------------------------------------------------`n-- GRANTS`n-- --------------------------------------------------------`n"
    $deploySql += ($allGrants -join "`n") + "`nGO`n"
}

Set-Content -LiteralPath (Join-Path $deployDir 'deploy.sql') -Value $deploySql -Encoding UTF8

# --- Build README ---
$readme = @"
# Deployment Guide -- $deployDate

**Target server:** $server
**Target database:** $database
**Deploy date:** $deployDate
**Baseline (for diffs):** $baseline
**Projects:** $($request.projects -join ', ')

---

## Overview

Full SQL installation package for **$($request.projects -join '** and **')**. All SQL objects under each project's ``SQL/`` folder are included (CREATE OR ALTER - safe to re-run). Web DLLs are staged from ``bin/`` when present.

---

## Changes Since Baseline

"@

$anyChanges = $false
foreach ($pd in $projectData) {
    if ($pd.changedFiles.Count -eq 0) {
        $readme += "`n### $($pd.projectName)`n`nNo file changes since ``$baseline``.`n"
        continue
    }
    $anyChanges = $true
    $readme += "`n### $($pd.projectName)`n`n"
    if ($pd.changedSql.Count -gt 0) {
        $readme += "**SQL (changed):**`n"
        foreach ($f in $pd.changedSql) { $readme += "- ``$f```n" }
    }
    if ($pd.changedCs.Count -gt 0) {
        $readme += "**C# / web (changed):**`n"
        foreach ($f in $pd.changedCs) {
            $subj = git log -1 --pretty=%s -- $f 2>$null
            if ($subj) { $readme += "- ``$f`` - $subj`n" }
            else { $readme += "- ``$f```n" }
        }
    }
    $other = $pd.changedFiles | Where-Object { $_ -notmatch '\.(sql|cs)$' }
    if ($other) {
        $readme += "**Other:**`n"
        foreach ($f in $other) { $readme += "- ``$f```n" }
    }
}

if (-not $anyChanges) {
    $readme += "`nNo file changes since ``$baseline`` across selected projects. Package is a full SQL reinstall.`n"
}

$readme += @"

---

## SQL Files Deployed (full install)

All ``*.sql`` files from each project's ``SQL/`` folder (excluding ``Tests/``, ``Old procs/``). Duplicates across projects (e.g. shared ``cx_job_ins``) are included once in ``deploy.sql``.

"@

foreach ($pd in $projectData) {
    $readme += "`n### $($pd.projectName) ($($pd.sqlFiles.Count) files)`n`n"
    $readme += "| # | File | Tier | Type |`n|---|------|------|------|`n"
    $i = 1
    foreach ($s in ($pd.sqlFiles | Sort-Object tier, path)) {
        $readme += "| $i | ``$($s.path)`` | $($s.tier) | $(Get-ObjectType $s.tier) |`n"
        $i++
    }
}

$readme += @"

---

## Combined deploy.sql Objects

| # | Object | Type | Source project | Notes |
|---|--------|------|----------------|-------|

"@

foreach ($o in $objects) {
    $readme += "| $($o.Number) | ``$($o.Name)`` | $($o.Type) | $($o.Project) | $($o.Notes) |`n"
}

$readme += @"

---

## Step 1 -- Run batch package

Unzip ``deploy-batch.zip`` on the batch server. Run ``Deploy-SQL.ps1`` as Administrator.
Runs numbered files in ``SQL/`` against **$database** on **$server**. Safe to re-run.

## Step 2 -- Run web package

Unzip ``deploy-web.zip`` on the web server. Run ``Deploy-Web.ps1`` as Administrator.
Target: **$webTarget**

"@

$step = 3
foreach ($pd in $projectData) {
    if ($pd.csFiles.Count -eq 0) { continue }
    $readme += "## Step $step -- Build and Deploy: $($pd.projectName)`n`n"
    $readme += "Build Release; copy DLLs and web assets (or use ``Deploy-Web.ps1`` from package).`n`n"
    $step++
}

Set-Content -LiteralPath (Join-Path $deployDir 'README.md') -Value $readme -Encoding UTF8

Write-Output "deploy.sql: $($objects.Count) objects"
Write-Output "README: $deployDir\README.md"
Write-Output "Projects: $($projectData.projectName -join ', ')"

if ($Flag -ne '--saas') { return }

# --- Package: stage batch + web, create ZIPs ---
$stageWeb = Join-Path $deployDir 'stage-web'
$stageBatch = Join-Path $deployDir 'stage-batch'
$wf = Join-Path $stageWeb 'WebFiles'
Remove-Item $stageWeb, $stageBatch -Recurse -Force -ErrorAction SilentlyContinue
foreach ($d in @("$wf\bin", "$wf/Custom", "$wf/Custom/Config", "$wf/Custom/Styles", "$wf/Custom/scripts", "$wf/Images")) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}
New-Item -ItemType Directory -Path (Join-Path $stageBatch 'SQL') -Force | Out-Null

# Batch: numbered SQL files (full install)
$seq = 1
foreach ($item in ($allSql | Sort-Object tier, path)) {
    $src = Join-Path $RepoRoot ($item.path -replace '/', '\')
    $destName = '{0:D2}_{1}' -f $seq, (Split-Path $item.path -Leaf)
    Copy-Item $src (Join-Path $stageBatch "SQL\$destName") -Force
    $seq++
}

Copy-Item (Join-Path $deployDir 'README.md') $stageBatch -Force
Copy-Item (Join-Path $deployDir 'deploy.sql') $stageBatch -Force

$deploySqlPs1 = @"
# Deploy-SQL.ps1 - $($request.environment) deployment $deployDate
param([string]`$LogDir = "F:\batch\log")
Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"
Write-Host "--- SQL deployment $deployDate starting ---"
. "F:\batch\bin\set_env.ps1"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$sqlDir    = Join-Path `$scriptDir "SQL"
if (-not (Test-Path `$LogDir)) { New-Item -ItemType Directory -Force `$LogDir | Out-Null }
`$files = Get-ChildItem "`$sqlDir\*.sql" | Sort-Object Name
`$i = 0; `$total = `$files.Count
foreach (`$file in `$files) {
    `$i++; `$scriptName = [IO.Path]::GetFileNameWithoutExtension(`$file.Name)
    Write-Host "[`$i/`$total] `$(`$file.Name)"
    & "F:\batch\bin\cx_call_sql.ps1" -scriptName `$scriptName -sqlScript `$file.FullName -logDir `$LogDir -dbServer `$env:DBSOURCECKB -dbName `$env:DBNAMECKB -dbUser `$env:DBUSER -dbPwd `$env:DBPWD
    if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
}
Write-Host "--- SQL deployment complete (`$total files) ---"
"@
Set-Content -LiteralPath (Join-Path $stageBatch 'Deploy-SQL.ps1') -Value $deploySqlPs1 -Encoding ASCII

# Web: stage from each project's bin/Views/CSS/JS if present
foreach ($proj in $request.projects) {
    $root = Join-Path $RepoRoot $proj
    $binDirs = @(
        (Join-Path $root 'bin'),
        (Join-Path $root 'bin\Release'),
        (Join-Path $root 'bin\Debug')
    )
    foreach ($bd in $binDirs) {
        if (Test-Path $bd) {
            Get-ChildItem $bd -Filter '*.dll' -ErrorAction SilentlyContinue | Copy-Item -Destination "$wf\bin\" -Force -ErrorAction SilentlyContinue
            Get-ChildItem $bd -Filter '*.dll.config' -ErrorAction SilentlyContinue | Copy-Item -Destination "$wf\bin\" -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($sub in @('Views', 'CSS', 'Css', 'Javascript', 'JavaScript', 'Images')) {
        $p = Join-Path $root $sub
        if (-not (Test-Path $p)) { continue }
        switch ($sub) {
            'Views' { Copy-Item "$p\*.ascx" "$wf\Custom\" -Force -ErrorAction SilentlyContinue; Copy-Item "$p\..\HelperClasses\*.ashx" "$wf\Custom\" -Force -ErrorAction SilentlyContinue }
            { $_ -in 'CSS', 'Css' } { Copy-Item "$p\*.css" "$wf\Custom\Styles\" -Force -ErrorAction SilentlyContinue }
            { $_ -in 'Javascript', 'JavaScript' } { Copy-Item "$p\*.js" "$wf\Custom\scripts\" -Force -ErrorAction SilentlyContinue }
            'Images' { Copy-Item "$p\*" "$wf\Images\" -Force -ErrorAction SilentlyContinue }
        }
    }
    $cfg = Join-Path $root 'Config\CrispCustomizations.config'
    if (-not (Test-Path $cfg)) { $cfg = Join-Path $RepoRoot 'Config\CrispCustomizations.config' }
    if (Test-Path $cfg) { Copy-Item $cfg "$wf\Custom\Config\" -Force }
}

Copy-Item (Join-Path $deployDir 'README.md') $stageWeb -Force

$deployWebPs1 = @"
# Deploy-Web.ps1 - $($request.environment) deployment $deployDate
param([string]`$WebTarget = "$webTarget")
Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$webFiles  = Join-Path `$scriptDir "WebFiles"
if (-not (Test-Path `$webFiles)) { Write-Host "ERROR: WebFiles not found"; exit 1 }
Write-Host "--- Web deployment $deployDate -> `$WebTarget ---"
`$dirs = @("Custom","Custom/Config","Custom/Styles","Custom/scripts","bin","Images")
foreach (`$d in `$dirs) { `$t = Join-Path `$WebTarget `$d; if (-not (Test-Path `$t)) { New-Item -ItemType Directory -Force `$t | Out-Null } }
Copy-Item "`$webFiles\Custom\*.ascx"     (Join-Path `$WebTarget "Custom")         -Force -ErrorAction SilentlyContinue
Copy-Item "`$webFiles\Custom\*.ashx"     (Join-Path `$WebTarget "Custom")         -Force -ErrorAction SilentlyContinue
Copy-Item "`$webFiles\Custom\Config\*"   (Join-Path `$WebTarget "Custom/Config")  -Force -ErrorAction SilentlyContinue
Copy-Item "`$webFiles\Custom\Styles\*"   (Join-Path `$WebTarget "Custom/Styles")  -Force -ErrorAction SilentlyContinue
Copy-Item "`$webFiles\Custom\scripts\*"  (Join-Path `$WebTarget "Custom/scripts") -Force -ErrorAction SilentlyContinue
Copy-Item "`$webFiles\bin\*"             (Join-Path `$WebTarget "bin")             -Force -ErrorAction SilentlyContinue
Copy-Item "`$webFiles\Images\*"          (Join-Path `$WebTarget "Images")          -Force -ErrorAction SilentlyContinue
Write-Host "--- Web deployment complete ---"
"@
Set-Content -LiteralPath (Join-Path $stageWeb 'Deploy-Web.ps1') -Value $deployWebPs1 -Encoding ASCII

Remove-Item (Join-Path $deployDir 'deploy-web.zip'), (Join-Path $deployDir 'deploy-batch.zip') -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$stageWeb\*" -DestinationPath (Join-Path $deployDir 'deploy-web.zip') -Force
Compress-Archive -Path "$stageBatch\*" -DestinationPath (Join-Path $deployDir 'deploy-batch.zip') -Force

Write-Output "deploy-web.zip: $(Join-Path $deployDir 'deploy-web.zip')"
Write-Output "deploy-batch.zip: $(Join-Path $deployDir 'deploy-batch.zip')"
Write-Output "Batch SQL files: $($seq - 1)"
