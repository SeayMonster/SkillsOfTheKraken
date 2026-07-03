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
    [string]$Flag = '--saas',
    [ValidateSet('All', 'Stage', 'Zip')]
    [string]$Phase = 'All'
)

$ErrorActionPreference = 'Stop'
Set-Location $RepoRoot

function Get-Tier([string]$path) {
    $leaf = Split-Path $path -Leaf
    if ($path -match '[\\/]Types[\\/]') { return 0 }
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
        0 { 'Type' }
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
        0 { 'TYPES' }
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
    # cx_call_sql uses ADO.NET ExecuteNonQuery -- GO is not valid T-SQL; strip all batch separators
    $text = [regex]::Replace($text, '(?im)^\s*GO\s*$[\r\n]*', '')
    # Strip SET ANSI_NULLS / SET QUOTED_IDENTIFIER -- only meaningful with GO batch separators;
    # without GO they land in the same batch as CREATE/ALTER PROCEDURE and cause a parse error
    $text = [regex]::Replace($text, '(?im)^\s*SET\s+ANSI_NULLS\s+(?:ON|OFF)\s*$[\r\n]*', '')
    $text = [regex]::Replace($text, '(?im)^\s*SET\s+QUOTED_IDENTIFIER\s+(?:ON|OFF)\s*$[\r\n]*', '')
    return $text.Trim()
}

function Extract-Grants([string]$content) {
    $grants = [System.Collections.Generic.List[string]]::new()
    $body = $content.TrimEnd()

    while ($body -match '(?is)(?<body>.*)\r?\n(?<grant>GRANT[\s\S]+?TO\s+(?:PUBLIC|\[[^\]]+\]|[^\s\r\n;]+))\s*;?\s*$') {
        $newBody = $Matches['body'].TrimEnd()
        if ($newBody.Length -ge $body.Length) { break }
        $g = ($Matches['grant'] -replace '\r?\n', ' ' -replace '\s+', ' ').Trim()
        if ($g -and $g -notmatch ';$') { $g += ';' }
        if ($g -and $grants -notcontains $g) { [void]$grants.Insert(0, $g) }
        $body = $newBody
    }

    foreach ($m in [regex]::Matches($body, '(?im)^\s*GRANT\s+.+?;\s*$')) {
        $g = $m.Value.Trim()
        if ($grants -notcontains $g) { [void]$grants.Add($g) }
        $body = $body.Remove($m.Index, $m.Length)
    }

    return @{ Body = $body.Trim(); Grants = @($grants) }
}

function Test-BatchSqlFiles([string]$sqlDir) {
    $errors = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem $sqlDir -Filter '*.sql' | ForEach-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        if ($text -match '(?im)^\s*GO\s*$') {
            [void]$errors.Add("$($_.Name): contains GO (invalid for cx_call_sql / ADO.NET)")
        }
        if ($_.Name -notmatch 'grants\.sql$') {
            if ($text -match '(?is)\bEND\s*;?\s*\r?\n\s*GRANT\s') {
                [void]$errors.Add("$($_.Name): GRANT after END -- extract to *_grants.sql")
            }
            if ($text -match '(?is)\)\s*;?\s*\r?\n\s*GRANT\s') {
                [void]$errors.Add("$($_.Name): GRANT after VIEW/DDL -- extract to *_grants.sql")
            }
            # SET ANSI_NULLS / SET QUOTED_IDENTIFIER without GO cause "CREATE/ALTER must be first statement" error
            if ($text -match '(?im)^\s*SET\s+ANSI_NULLS\s') {
                [void]$errors.Add("$($_.Name): SET ANSI_NULLS present -- Clean-SqlContent should have stripped this")
            }
            if ($text -match '(?im)^\s*SET\s+QUOTED_IDENTIFIER\s') {
                [void]$errors.Add("$($_.Name): SET QUOTED_IDENTIFIER present -- Clean-SqlContent should have stripped this")
            }
        }
    }
    if ($errors.Count -gt 0) {
        throw ("Batch SQL validation failed (cx_call_sql rules):`n" + ($errors -join "`n"))
    }
}

$script:ProjectCodeCache = @{}

function Get-ProjectCodeCache([string]$projectRoot) {
    # Read every .cs/.sql file's content ONCE per project (not once per proc) -- with N procs
    # per project, checking membership per-proc instead of rescanning disk per-proc turns an
    # O(N) file-tree walk into O(N^2). Cache keyed by project root.
    if ($script:ProjectCodeCache.ContainsKey($projectRoot)) { return $script:ProjectCodeCache[$projectRoot] }
    $entries = Get-ChildItem $projectRoot -Recurse -Include '*.cs', '*.sql' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\obj\\|\\bin\\' } |
        ForEach-Object { [PSCustomObject]@{ Path = $_.FullName; Content = (Get-Content -LiteralPath $_.FullName -Raw) } }
    $script:ProjectCodeCache[$projectRoot] = $entries
    return $entries
}

function Test-ProcUsedInCode([string]$projectRoot, [string]$procName, [string]$selfPath) {
    # Check .cs (CommandFactory etc.) AND .sql (proc-to-proc EXEC chains -- orchestrator procs
    # calling action procs never touch C# at all) so we don't drop something still wired up
    # internally. Erring toward "keep it" is the safe direction for a deploy filter.
    foreach ($entry in (Get-ProjectCodeCache $projectRoot)) {
        if ($entry.Path -eq $selfPath) { continue }
        if ($entry.Content.IndexOf($procName, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Get-AllSqlFiles([string]$projectName) {
    $root = Join-Path $RepoRoot $projectName
    $sqlRoot = Join-Path $root 'SQL'
    if (-not (Test-Path $sqlRoot)) { return @() }
    Get-ChildItem $sqlRoot -Recurse -Filter '*.sql' -File |
        Where-Object {
            $_.FullName -notmatch '\\Tests\\|\\Test Data\\|\\Old procs\\|\\\.vs\\|\\.git\\' -and
            $_.Name -notmatch '^reset_and_test\.'
        } |
        Where-Object { $_.Length -gt 0 } |
        ForEach-Object {
            $rel = $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
            $tier = Get-Tier $rel
            # Stored procs no longer called from any .cs file are stale (renamed/replaced) -- drop them
            # so packages don't keep re-deploying dead code (Types/Views/Tables aren't filtered this way,
            # since they're often referenced only via raw SQL text, not a C# symbol). Maintenance scripts
            # (e.g. drop-old-procs cleanup) don't define a CREATE PROCEDURE at all -- exempt, always keep.
            if ($tier -eq 5) {
                $definesProc = Select-String -LiteralPath $_.FullName -Pattern '(?im)^\s*CREATE\s+(OR\s+ALTER\s+)?PROCEDURE\b' -Quiet
                if ($definesProc) {
                    $procName = [IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '^ckbcustom\.', ''
                    if (-not (Test-ProcUsedInCode $root $procName $_.FullName)) {
                        Write-Host "  Skipping stale proc (not referenced in $projectName code): $procName" -ForegroundColor Yellow
                        return
                    }
                }
            }
            [PSCustomObject]@{ path = $rel; tier = $tier; project = $projectName }
        }
}

function Invoke-PostPackageCleanup([string]$deployDir, [string]$repoRoot) {
    $removed = @()
    foreach ($dir in @('stage-web', 'stage-batch')) {
        $path = Join-Path $deployDir $dir
        if (Test-Path $path) {
            Remove-Item $path -Recurse -Force
            $removed += $dir
        }
    }
    $requestPath = Join-Path $repoRoot '_package-request.json'
    if (Test-Path $requestPath) {
        Remove-Item $requestPath -Force
        $removed += '_package-request.json'
    }
    $workingState = Join-Path $repoRoot '.kraken-cursor\deploy-state-working.json'
    if (Test-Path $workingState) {
        Remove-Item $workingState -Force
        $removed += '.kraken-cursor/deploy-state-working.json'
    }
    if ($removed.Count -gt 0) {
        Write-Output ("Cleanup removed: " + ($removed -join ', '))
    }
}

function Get-ChangedFiles([string]$projectName, [string]$baseline) {
    $files = @()
    $headOut = cmd /c "git diff --name-only $baseline HEAD -- `"$projectName/`" 2>nul"
    if ($headOut) { $files += ($headOut -split "`r?`n" | Where-Object { $_ }) }
    $workOut = cmd /c "git diff --name-only $baseline -- `"$projectName/`" 2>nul"
    if ($workOut) {
        foreach ($f in ($workOut -split "`r?`n" | Where-Object { $_ })) {
            if ($files -notcontains $f) { $files += $f }
        }
    }
    $files | Where-Object {
        $_ -and $_ -notmatch '\.(md|csproj|sqlproj|sln|json|ps1|html)$' `
            -and $_ -notmatch 'Tests/|Old procs/|Deployments/|docs/|\.claude/'
    }
}

# --- Zip phase: compress existing stage dirs and cleanup, then exit ---
if ($Phase -eq 'Zip') {
    $requestPath = Join-Path $RepoRoot '_package-request.json'
    $request = Get-Content $requestPath -Raw | ConvertFrom-Json
    $deployDate = Get-Date -Format 'yyyy-MM-dd'
    $deployDir = Join-Path $RepoRoot "Deployments\$deployDate"
    $stageBatch = Join-Path $deployDir 'stage-batch'
    $stageWeb   = Join-Path $deployDir 'stage-web'
    if (-not (Test-Path $stageBatch)) { throw "stage-batch not found at $stageBatch -- run -Phase Stage first" }
    Remove-Item (Join-Path $deployDir 'deploy-web.zip'), (Join-Path $deployDir 'deploy-batch.zip') -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path "$stageWeb\*"   -DestinationPath (Join-Path $deployDir 'deploy-web.zip')   -Force
    Compress-Archive -Path "$stageBatch\*" -DestinationPath (Join-Path $deployDir 'deploy-batch.zip') -Force
    Invoke-PostPackageCleanup -deployDir $deployDir -repoRoot $RepoRoot
    Write-Output "deploy-web.zip:   $(Join-Path $deployDir 'deploy-web.zip')"
    Write-Output "deploy-batch.zip: $(Join-Path $deployDir 'deploy-batch.zip')"
    return
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
if ($baseline) {
    $tagExists = git tag -l $baseline 2>$null
    if (-not $tagExists) {
        Write-Warning "Baseline tag '$baseline' not found -- falling back to latest deploy tag."
        $baseline = $null
    }
}
if (-not $baseline) {
    $baseline = git tag --list "deploy/$($request.environment)/*" --sort=-version:refname | Select-Object -First 1
    if (-not $baseline) { throw "No deploy tag found for $($request.environment). Set baseline in _package-request.json." }
}
Write-Output "Baseline: $baseline"

$deployDate = Get-Date -Format 'yyyy-MM-dd'
$deployDir = Join-Path $RepoRoot "Deployments\$deployDate"
$webTarget = if ($request.webTarget) { $request.webTarget } else { 'U:\OpenAccess\Customization\' }
$batchTarget = if ($request.batchTarget) { $request.batchTarget } else { 'F:\batch\exe' }
$commitMessages = @(git log "$baseline..HEAD" --pretty='%s' 2>$null)

New-Item -ItemType Directory -Path $deployDir -Force | Out-Null

# --- Version bump (per-project, optional) ---
# If a project contains version.json, auto-increment the minor version,
# update the target source file, and rebuild the DLL before staging.
# version.json schema: { "version": "1.5", "versionFile": "Views/MyControl.ascx.cs" }
$msbuildExe = $null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $found = & $vswhere -latest -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' 2>$null | Select-Object -First 1
    if ($found) { $msbuildExe = $found }
}
if (-not $msbuildExe) {
    foreach ($p in @(
        'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe'
    )) { if ((Test-Path $p) -and -not $msbuildExe) { $msbuildExe = $p } }
}

foreach ($proj in $request.projects) {
    $versionPath = Join-Path $RepoRoot "$proj\version.json"
    if (-not (Test-Path $versionPath)) { continue }

    $verData = Get-Content $versionPath -Raw | ConvertFrom-Json
    $oldVer  = $verData.version
    $parts   = $oldVer -split '\.'
    $parts[-1] = [int]$parts[-1] + 1
    $newVer  = $parts -join '.'

    $targetPath = Join-Path $RepoRoot "$proj\$($verData.versionFile)"
    if (Test-Path $targetPath) {
        $content = (Get-Content $targetPath -Raw) -replace "v$([regex]::Escape($oldVer))\b", "v$newVer"
        Set-Content $targetPath $content -Encoding UTF8 -NoNewline
    }

    $verData.version = $newVer
    $verData | ConvertTo-Json | Set-Content $versionPath -Encoding UTF8

    Write-Output "  Version: $proj v$oldVer -> v$newVer"

    if ($msbuildExe) {
        $csproj = Get-ChildItem (Join-Path $RepoRoot $proj) -Filter '*.csproj' -File | Select-Object -First 1
        if ($csproj) {
            Write-Output "  Rebuilding $proj..."
            & $msbuildExe $csproj.FullName /p:Configuration=Debug /p:PostBuildEvent='' /verbosity:minimal
            if ($LASTEXITCODE -ne 0) { throw "MSBuild failed for $proj after version bump" }
        }
    } else {
        Write-Warning "MSBuild not found -- v$newVer written to source but DLL not rebuilt. Build manually."
    }
}

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

# --- Build manual-deploy-fallback.sql (SSMS fallback; not run by Deploy-SQL.ps1) ---
$objects = @()
$allGrants = [System.Collections.Generic.List[string]]::new()
$tierBodies = @{ 0 = @(); 1 = @(); 2 = @(); 3 = @(); 4 = @(); 5 = @(); 99 = @() }
$num = 1
$sqlCache = @{}  # path -> parsed result; avoids reading + cleaning each file twice

foreach ($item in ($allSql | Sort-Object tier, path)) {
    $fullPath = Join-Path $RepoRoot ($item.path -replace '/', '\')
    $raw = Get-Content -Raw -LiteralPath $fullPath
    $clean = Clean-SqlContent $raw
    $parsed = Extract-Grants $clean
    $sqlCache[$item.path] = $parsed  # cache for batch staging loop
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
foreach ($tier in 0, 1, 2, 3, 4, 5) {
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

Set-Content -LiteralPath (Join-Path $deployDir 'manual-deploy-fallback.sql') -Value $deploySql -Encoding UTF8

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

## SQL deployment paths

This package ships the same SQL in two forms - use **one** path, not both.

| Location | Method | When to use |
|----------|--------|-------------|
| ``SQL/01_*.sql`` ... ``SQL/$('{0:D2}' -f $objects.Count)_*.sql`` | **Automated (normal)** - run ``Deploy-SQL.ps1`` on the batch server | Standard SaaS deploy. Each file runs in order via ``cx_call_sql.ps1``. |
| ``manual-deploy-fallback.sql`` (batch zip **root**, not under ``SQL/``) | **Manual (SSMS fallback)** - open in SSMS and execute | Batch automation unavailable, or review the full script before deploy. |

**Why ``manual-deploy-fallback.sql`` is at the zip root:** ``Deploy-SQL.ps1`` runs every ``*.sql`` in ``SQL/``. If the combined script were in ``SQL/``, deploy would run all objects twice (numbered files, then the combined script). Root placement keeps automated and manual paths separate.

Both paths deploy the same **$($objects.Count)** deduplicated objects (CREATE OR ALTER - safe to re-run).

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

All ``*.sql`` files from each project's ``SQL/`` folder (excluding ``Tests/``, ``Old procs/``). Duplicates across projects (e.g. shared ``cx_job_ins``) are included once in ``manual-deploy-fallback.sql`` and once each in the numbered ``SQL/`` files for batch deploy.

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

## Combined manual-deploy-fallback.sql Objects

| # | Object | Type | Source project | Notes |
|---|--------|------|----------------|-------|

"@

foreach ($o in $objects) {
    $readme += "| $($o.Number) | ``$($o.Name)`` | $($o.Type) | $($o.Project) | $($o.Notes) |`n"
}

$readme += @"

---

## Step 1 -- Run batch package (automated SQL)

Unzip ``deploy-batch.zip`` on the batch server. Run ``Deploy-SQL.ps1`` as Administrator.
Runs numbered files in ``SQL/`` only (does **not** run ``manual-deploy-fallback.sql``) against **$database** on **$server**. Safe to re-run.

**SSMS fallback (optional):** Instead of Step 1, open ``manual-deploy-fallback.sql`` from the batch zip root in SSMS and execute against **$database** on **$server**. Do not run both paths.

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

if ($Flag -ne '--saas') {
    Write-Output "manual-deploy-fallback.sql: $($objects.Count) objects"
    Write-Output "README: $deployDir\README.md"
    Write-Output "Projects: $($projectData.projectName -join ', ')"
    return
}

# --- Package: stage batch + web, create ZIPs ---
$stageWeb = Join-Path $deployDir 'stage-web'
$stageBatch = Join-Path $deployDir 'stage-batch'
$wf = Join-Path $stageWeb 'WebFiles'
Remove-Item $stageWeb, $stageBatch -Recurse -Force -ErrorAction SilentlyContinue
foreach ($d in @("$wf\bin", "$wf/Custom", "$wf/Custom/Config", "$wf/Custom/Styles", "$wf/Custom/scripts", "$wf/Custom/Templates", "$wf/Images")) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}
New-Item -ItemType Directory -Path (Join-Path $stageBatch 'SQL') -Force | Out-Null

# Batch: numbered SQL files -- use cached parsed content from loop 1 (no re-read, no re-clean)
$seq = 1
foreach ($item in ($allSql | Sort-Object tier, path)) {
    $destName = '{0:D2}_{1}' -f $seq, (Split-Path $item.path -Leaf)
    $parsed = $sqlCache[$item.path]
    Set-Content -LiteralPath (Join-Path $stageBatch "SQL\$destName") -Value $parsed.Body -Encoding UTF8 -NoNewline
    Add-Content -LiteralPath (Join-Path $stageBatch "SQL\$destName") -Value "" -Encoding UTF8
    $seq++
}
if ($allGrants.Count -gt 0) {
    $grantSql = ($allGrants | ForEach-Object { if ($_ -notmatch ';$') { $_ + ';' } else { $_ } }) -join "`r`n"
    Set-Content -LiteralPath (Join-Path $stageBatch "SQL\$('{0:D2}_grants.sql' -f $seq)") -Value $grantSql -Encoding UTF8
    $seq++
}
Test-BatchSqlFiles (Join-Path $stageBatch 'SQL')

Copy-Item (Join-Path $deployDir 'README.md') $stageBatch -Force
Copy-Item (Join-Path $deployDir 'manual-deploy-fallback.sql') $stageBatch -Force

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

# Web: stage from each project's bin/Views/CSS/JS if present (Release preferred; no pdb/vshost)
foreach ($proj in $request.projects) {
    $root = Join-Path $RepoRoot $proj
    $releaseBin = Join-Path $root 'bin\Release'
    $binDirs = if (Test-Path $releaseBin) { @($releaseBin) } else { @((Join-Path $root 'bin')) }
    foreach ($bd in $binDirs) {
        if (-not (Test-Path $bd)) { continue }
        Get-ChildItem $bd -Filter '*.dll' -ErrorAction SilentlyContinue |
            Where-Object {
                $n = $_.Name
                $n -match '\.dll$' -and $n -notmatch '\.vshost\.' -and
                $n -notmatch 'Serilog|PlanogramUpdater|^JDA\.|^Microsoft\.|^System\.|^Newtonsoft\.|^Azure\.' -and (
                    $n -match '^CX\.' -or
                    $n -match '^Cantactix\.OpenAccess\.Automator\.' -or
                    $n -match '^(ClosedXML|DocumentFormat\.OpenXml|ExcelDataReader|ExcelNumberFormat|RBush|SixLabors\.Fonts|System\.IO\.Packaging|Dapper)\.'
                )
            } |
            Copy-Item -Destination "$wf/bin\" -Force -ErrorAction SilentlyContinue
        Get-ChildItem $bd -Filter '*.dll.config' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^(CX\.|Cantactix\.OpenAccess\.Automator)\.dll\.config$' -and
                (Get-Content $_.FullName -Raw) -notmatch 'Serilog'
            } |
            Copy-Item -Destination "$wf/bin\" -Force -ErrorAction SilentlyContinue
    }
    foreach ($sub in @('Views', 'CSS', 'Css', 'Javascript', 'JavaScript', 'Images', 'Templates')) {
        $p = Join-Path $root $sub
        if (-not (Test-Path $p)) { continue }
        switch ($sub) {
            'Views' { Copy-Item "$p\*.ascx" "$wf\Custom\" -Force -ErrorAction SilentlyContinue; Copy-Item "$p\..\HelperClasses\*.ashx" "$wf\Custom\" -Force -ErrorAction SilentlyContinue; Copy-Item "$p\..\HelperClasses\*.aspx" "$wf\Custom\" -Force -ErrorAction SilentlyContinue }
            { $_ -in 'CSS', 'Css' } { Copy-Item "$p\*.css" "$wf\Custom\Styles\" -Force -ErrorAction SilentlyContinue }
            { $_ -in 'Javascript', 'JavaScript' } { Copy-Item "$p\*.js" "$wf\Custom\scripts\" -Force -ErrorAction SilentlyContinue }
            'Images' { Copy-Item "$p\*" "$wf\Images\" -Force -ErrorAction SilentlyContinue }
            'Templates' { Copy-Item "$p\*" "$wf\Custom\Templates\" -Force -ErrorAction SilentlyContinue }
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
`$dirs = @("Custom","Custom/Config","Custom/Styles","Custom/scripts","Custom/Templates","bin","Images")
foreach (`$d in `$dirs) { `$t = Join-Path `$WebTarget `$d; if (-not (Test-Path `$t)) { New-Item -ItemType Directory -Force `$t | Out-Null } }
function Copy-AndLog {
    param([string]`$Filter, [string]`$Dest)
    `$files = Get-ChildItem `$Filter -File -ErrorAction SilentlyContinue
    foreach (`$f in `$files) {
        Copy-Item `$f.FullName `$Dest -Force -ErrorAction SilentlyContinue
        Write-Host "  `$(`$f.Name) -> `$Dest"
    }
}
Copy-AndLog "`$webFiles\Custom\*.ascx"      (Join-Path `$WebTarget "Custom")
Copy-AndLog "`$webFiles\Custom\*.ashx"      (Join-Path `$WebTarget "Custom")
Copy-AndLog "`$webFiles\Custom\*.aspx"      (Join-Path `$WebTarget "Custom")
Copy-AndLog "`$webFiles\Custom\Config\*"    (Join-Path `$WebTarget "Custom/Config")
Copy-AndLog "`$webFiles\Custom\Styles\*"    (Join-Path `$WebTarget "Custom/Styles")
Copy-AndLog "`$webFiles\Custom\scripts\*"   (Join-Path `$WebTarget "Custom/scripts")
Copy-AndLog "`$webFiles\Custom\Templates\*" (Join-Path `$WebTarget "Custom/Templates")
Copy-AndLog "`$webFiles\bin\*"              (Join-Path `$WebTarget "bin")
Copy-AndLog "`$webFiles\Images\*"           (Join-Path `$WebTarget "Images")
Write-Host "--- Web deployment complete ---"
"@
Set-Content -LiteralPath (Join-Path $stageWeb 'Deploy-Web.ps1') -Value $deployWebPs1 -Encoding ASCII

# --- Stage phase: exit before zipping so workflow can run the Validate agent ---
if ($Phase -eq 'Stage') {
    $sqlCount = (Get-ChildItem (Join-Path $stageBatch 'SQL') -Filter '*.sql').Count
    Write-Output "manual-deploy-fallback.sql: $($objects.Count) objects"
    Write-Output "README: $deployDir\README.md"
    Write-Output "Projects: $($projectData.projectName -join ', ')"
    Write-Output "Stage complete: stage-batch\SQL has $sqlCount files -- run Validate then -Phase Zip"
    return
}

Remove-Item (Join-Path $deployDir 'deploy-web.zip'), (Join-Path $deployDir 'deploy-batch.zip') -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$stageWeb\*" -DestinationPath (Join-Path $deployDir 'deploy-web.zip') -Force
Compress-Archive -Path "$stageBatch\*" -DestinationPath (Join-Path $deployDir 'deploy-batch.zip') -Force

Invoke-PostPackageCleanup -deployDir $deployDir -repoRoot $RepoRoot

Write-Output "deploy-web.zip: $(Join-Path $deployDir 'deploy-web.zip')"
Write-Output "deploy-batch.zip: $(Join-Path $deployDir 'deploy-batch.zip')"
Write-Output "Batch SQL files: $($seq - 1)"
Write-Output "Kept in $deployDir : README.md, manual-deploy-fallback.sql, deploy-*.zip, component guides (*.md, *.xlsx)"
