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
. (Join-Path $PSScriptRoot 'PackageLib.ps1')

function Get-ObjectName([string]$path) {
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    if ($name -match '^ckbcustom\.') { return $name.ToLower() }
    if ($path -match '[\\/]Configuration[\\/]') { return $name.ToLower() }
    return "ckbcustom.$name".ToLower()
}

function Clean-SqlContent([string]$content) {
    $lines = $content -split "`r?`n"
    if ($lines.Count -gt 0) { $lines[0] = $lines[0].TrimStart([char]0xFEFF) }
    $text = ($lines -join "`r`n").Trim()
    # Replace em-dashes (U+2014) with ASCII hyphens -- cx_call_sql rejects non-ASCII in some envs
    $text = $text -replace [char]0x2014, '-'
    $text = [regex]::Replace($text, '(?is)^\s*USE\s+\[?\w+\]?\s*\r?\nGO\s*\r?\n', '')
    # cx_call_sql uses ADO.NET ExecuteNonQuery -- GO is not valid T-SQL; strip all batch separators
    $text = [regex]::Replace($text, '(?im)^\s*GO\s*$[\r\n]*', '')
    # Strip SET ANSI_NULLS / SET QUOTED_IDENTIFIER -- only meaningful with GO batch separators;
    # without GO they land in the same batch as CREATE/ALTER PROCEDURE and cause a parse error
    $text = [regex]::Replace($text, '(?im)^\s*SET\s+ANSI_NULLS\s+(?:ON|OFF)\s*;?\s*$[\r\n]*', '')
    $text = [regex]::Replace($text, '(?im)^\s*SET\s+QUOTED_IDENTIFIER\s+(?:ON|OFF)\s*;?\s*$[\r\n]*', '')
    # Convert SSMS-style DROP+CREATE into CREATE OR ALTER -- without GO, DROP and CREATE land in the
    # same batch and SQL Server requires CREATE PROCEDURE to be the first statement (error 111).
    # Strip the IF OBJECT_ID...DROP PROCEDURE guard (the OR ALTER handles idempotency instead).
    $text = [regex]::Replace($text, '(?im)^\s*IF\s+OBJECT_ID\s*\([^)]+,\s*''P''\s*\)\s+IS\s+NOT\s+NULL\r?\n\s*DROP\s+PROCEDURE\s+[^\r\n]+;?\r?\n?', '')
    $text = [regex]::Replace($text, '(?im)^\s*DROP\s+PROCEDURE\s+IF\s+EXISTS\s+[^\r\n]+;?\r?\n?', '')
    $text = [regex]::Replace($text, '(?im)\bCREATE\s+PROCEDURE\b', 'CREATE OR ALTER PROCEDURE')
    return $text.Trim()
}

function Extract-Grants([string]$content) {
    # Fast path: no GRANT in file at all
    if ($content.IndexOf('GRANT', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return @{ Body = $content.Trim(); Grants = @() }
    }

    $lines = $content -split "`r?`n"
    $grants = [System.Collections.Generic.List[string]]::new()
    $cutAt = $lines.Count  # index of first trailing GRANT line

    # Walk backwards: collect trailing GRANT blocks (single or multi-line).
    # Multi-line GRANTs have continuation lines (ON ..., TO ...) before the GRANT keyword.
    $grantLines = [System.Collections.Generic.List[string]]::new()
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $t = $lines[$i].Trim()
        if ($t -eq '' -or $t -match '^--') { continue }
        if ($t -match '^GRANT\b') {
            # Complete GRANT keyword found -- build the full statement
            $grantLines.Insert(0, $t)
            $g = ($grantLines -join ' ') -replace '\s+', ' '
            $g = $g.Trim(); if ($g -notmatch ';$') { $g += ';' }
            if ($grants -notcontains $g) { [void]$grants.Insert(0, $g) }
            $grantLines = [System.Collections.Generic.List[string]]::new()
            $cutAt = $i
        } elseif ($t -match '^(ON|TO|WITH|AS)\b' -or $grantLines.Count -gt 0) {
            # Continuation line of a multi-line GRANT (ON schema.obj, TO PUBLIC, etc.)
            $grantLines.Insert(0, $t)
            $cutAt = $i
        } else {
            break
        }
    }

    $body = if ($cutAt -gt 0) { ($lines[0..($cutAt - 1)] -join "`r`n").Trim() } else { '' }
    return @{ Body = $body; Grants = @($grants) }
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
            if (-not (Test-ModuleCreateFirst $text)) {
                [void]$errors.Add("$($_.Name): CREATE PROCEDURE/FUNCTION/VIEW/TRIGGER is not the first statement -- use CREATE OR ALTER instead of DROP + CREATE")
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
        throw ("Batch SQL validation failed (one batch per file):`n" + ($errors -join "`n"))
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
        if ($entry.Content -and $entry.Content.IndexOf($procName, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Get-AllSqlFiles([string]$projectName) {
    $root = $projRoots[$projectName]
    $sqlRoot = Join-Path $root 'SQL'
    if (-not (Test-Path $sqlRoot)) { return @() }
    Get-ChildItem $sqlRoot -Recurse -Filter '*.sql' -File |
        Where-Object {
            $_.FullName -notmatch '\\Tests\\|\\Test Data\\|\\Old procs\\|\\\.vs\\|\\.git\\|\\Manual Scripts\\|\\Manual\\' -and
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
    foreach ($dir in @('stage-web', 'stage-batch', 'stage-sapro')) {
        $path = Join-Path $deployDir $dir
        if (Test-Path $path) {
            Remove-Item $path -Recurse -Force
            $removed += $dir
        }
    }
    foreach ($marker in @('_package-request.json', '_package-build.json')) {
        $mp = Join-Path $repoRoot $marker
        if (Test-Path $mp) { Remove-Item $mp -Force; $removed += $marker }
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

# Tag the packaged commit, record it as the next baseline, refresh the release
# README. Runs only after the zips exist.
function Complete-BuildStamp([string]$RepoRoot, $Pb) {
    git tag $Pb.tag 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warning "Could not create tag $($Pb.tag)" }
    [ordered]@{ release = $Pb.release; build = $Pb.build; tag = $Pb.tag; date = (Get-Date -Format 'yyyy-MM-dd') } |
        ConvertTo-Json | Set-Content (Join-Path $RepoRoot 'deploy-state.json') -Encoding UTF8
    New-ReleaseReadme (Split-Path $Pb.deployDir -Parent)
    Write-Output "Tagged $($Pb.tag)"
}

function Get-ChangedFiles([string]$projectName, [string]$baseline) {
    if (-not $baseline) { return @() }
    $files = @()
    $headOut = cmd /c "git diff --name-only $baseline HEAD -- `"$($projRels[$projectName])/`" 2>nul"
    if ($headOut) { $files += ($headOut -split "`r?`n" | Where-Object { $_ }) }
    $workOut = cmd /c "git diff --name-only $baseline -- `"$($projRels[$projectName])/`" 2>nul"
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
    $packageBuild = Get-Content (Join-Path $RepoRoot '_package-build.json') -Raw | ConvertFrom-Json
    $deployDir = $packageBuild.deployDir
    $stageBatch = Join-Path $deployDir 'stage-batch'
    $stageWeb   = Join-Path $deployDir 'stage-web'
    $stageSaPro = Join-Path $deployDir 'stage-sapro'
    if (-not (Test-Path $stageBatch)) { throw "stage-batch not found at $stageBatch -- run -Phase Stage first" }
    Remove-Item (Join-Path $deployDir 'deploy-web.zip'), (Join-Path $deployDir 'deploy-batch.zip') -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path "$stageWeb\*"   -DestinationPath (Join-Path $deployDir 'deploy-web.zip')   -Force
    Compress-Archive -Path "$stageBatch\*" -DestinationPath (Join-Path $deployDir 'deploy-batch.zip') -Force
    # SA Pro is optional: a repo with no Automation-referencing project has no stage dir.
    if (Test-Path $stageSaPro) {
        Compress-Archive -Path "$stageSaPro\*" -DestinationPath (Join-Path $deployDir 'deploy-sapro.zip') -Force
        Write-Output "deploy-sapro.zip: $(Join-Path $deployDir 'deploy-sapro.zip')"
    }
    Complete-BuildStamp $RepoRoot $packageBuild
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

# Project folders come from client.json (path), so nested projects such as
# BHN.Pog.Converter/CXBHNPogConverter work; an unlisted project is a folder of
# the same name, as before.
$clientCfg = Read-ClientConfig $RepoRoot
$projRoots = @{}
$projRels = @{}
foreach ($p in $request.projects) {
    $projRels[$p] = Get-ProjectRelPath $clientCfg $p
    $projRoots[$p] = Resolve-ProjectPath $RepoRoot $clientCfg $p
    if (-not (Test-Path $projRoots[$p])) { throw "Project folder not found for '$p': $($projRoots[$p])" }
}

# A package is environment-agnostic: the same zips go to Test, then Prod.
# env-config.json is optional and only names a server in the README;
# Deploy-SQL.ps1 takes the real connection from the batch server.
$server = 'the batch server (set_env.ps1)'
$database = 'CKB'
$envConfigPath = Join-Path $RepoRoot 'Environment Details\env-config.json'
if ($request.environment -and (Test-Path $envConfigPath)) {
    $envEntry = (Get-Content $envConfigPath -Raw | ConvertFrom-Json).($request.environment)
    if ($envEntry) { $server = $envEntry.Server; $database = $envEntry.Database }
}
$stateFile = Join-Path $RepoRoot 'deploy-state.json'
$stateTag = $null
if (Test-Path $stateFile) {
    try { $stateTag = (Get-Content $stateFile -Raw | ConvertFrom-Json).tag } catch { $stateTag = $null }
}
$deployTags = @(git tag --list 'deploy/*' --sort=-creatordate 2>$null)
$baseline = Resolve-Baseline $request.baseline $stateTag $deployTags
Write-Output ('Baseline: ' + $(if ($baseline) { $baseline } else { '(none - initial package)' }))

# --- Release and build ---
# Deployments\<release>\<NN>_<HHmm>\: a same-day patch is the next build,
# never an overwrite.
$release = if ($request.release) { [string]$request.release } else { Get-Date -Format 'yyyy-MM-dd' }
$releaseDir = Join-Path $RepoRoot "Deployments\$release"
$build = Get-NextBuild $releaseDir
$buildFolder = '{0:D2}_{1}' -f $build, (Get-Date -Format 'HHmm')
$deployDir = Join-Path $releaseDir $buildFolder
$buildTag = Get-BuildTag $release $build
$deployDate = Get-Date -Format 'yyyy-MM-dd'

# client.json targets win; a repo without them keeps the portal's request
# values (Academy sends a UNC batch path), then the built-in defaults.
function Select-Target([string]$Kind, $RequestValue) {
    if ($clientCfg.targets -and $clientCfg.targets.PSObject.Properties[$Kind]) { return Get-DeployTarget $clientCfg $Kind }
    if ($RequestValue) { return [string]$RequestValue }
    return Get-DeployTarget $clientCfg $Kind
}
$webTarget = Select-Target 'web' $request.webTarget
$batchTarget = Select-Target 'batch' $request.batchTarget
$saproTarget = Select-Target 'sapro' $null
$commitMessages = if ($baseline) { @(git log "$baseline..HEAD" --pretty='%s' 2>$null) } else { @() }

New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
$packageBuild = [PSCustomObject]@{ release = $release; build = $build; buildFolder = $buildFolder; deployDir = $deployDir; tag = $buildTag }
ConvertTo-Json $packageBuild | Set-Content (Join-Path $RepoRoot '_package-build.json') -Encoding UTF8
Write-Output "Build folder: $deployDir"

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

$rebuilt = @{}
foreach ($proj in $request.projects) {
    $versionPath = Join-Path $projRoots[$proj] 'version.json'
    if (-not (Test-Path $versionPath)) { continue }

    $verData = Get-Content $versionPath -Raw | ConvertFrom-Json
    $oldVer  = $verData.version
    $parts   = $oldVer -split '\.'
    $parts[-1] = [int]$parts[-1] + 1
    $newVer  = $parts -join '.'

    $targetPath = Join-Path $projRoots[$proj] $verData.versionFile
    if (Test-Path $targetPath) {
        $content = (Get-Content $targetPath -Raw) -replace "v$([regex]::Escape($oldVer))\b", "v$newVer"
        Set-Content $targetPath $content -Encoding UTF8 -NoNewline
    }

    $verData.version = $newVer
    $verData | ConvertTo-Json | Set-Content $versionPath -Encoding UTF8

    Write-Output "  Version: $proj v$oldVer -> v$newVer"

    if ($msbuildExe) {
        $csproj = Get-ChildItem $projRoots[$proj] -Filter '*.csproj' -File | Select-Object -First 1
        if ($csproj) {
            Write-Output "  Rebuilding $proj..."
            $rebuilt[$proj] = $true
            & $msbuildExe $csproj.FullName /p:Configuration=Release /p:PostBuildEvent='' /verbosity:minimal
            if ($LASTEXITCODE -ne 0) { throw "MSBuild failed for $proj after version bump" }
        }
    } else {
        Write-Warning "MSBuild not found -- v$newVer written to source but DLL not rebuilt. Build manually."
    }
}

# --- Build every selected project (Release) ---
# The package ships what is in bin, so build first: a stale or missing
# bin\Release would otherwise ship old DLLs or none (an SA Pro script that was
# never built in Release is silently left out). Projects rebuilt by the version
# bump above are not built twice; client.json "skip" projects and SQL-only
# projects (no .cs) are not built.
foreach ($proj in $request.projects) {
    if ($rebuilt.ContainsKey($proj)) { continue }
    $cp = Get-ClientProject $clientCfg $proj
    if ($cp -and $cp.target -eq 'skip') { continue }
    $csproj = Get-ChildItem $projRoots[$proj] -Filter '*.csproj' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $csproj) { continue }
    $csFiles = Get-ChildItem $projRoots[$proj] -Filter '*.cs' -Recurse -ErrorAction SilentlyContinue
    if (-not $csFiles) { continue }
    if (-not $msbuildExe) {
        Write-Warning "MSBuild not found -- $proj not built; packaging whatever is in its bin folder."
        continue
    }
    Write-Output "  Building $proj (Release)..."
    & $msbuildExe $csproj.FullName /p:Configuration=Release /p:PostBuildEvent='' /verbosity:minimal /nologo
    if ($LASTEXITCODE -ne 0) { throw "MSBuild failed for $proj" }
}

# --- Gather: ALL SQL (full install) + diffs for README ---
$projectData = [System.Collections.Generic.List[object]]::new()
$allSql = [System.Collections.Generic.List[object]]::new()
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
            [void]$allSql.Add($s)
        }
    }

    [void]$projectData.Add([PSCustomObject]@{
        projectName  = $proj
        projectRoot  = "$($projRels[$proj])/"
        sqlFiles     = $sqlFiles
        csFiles      = @($changedCs | ForEach-Object { [PSCustomObject]@{ path = $_ } })
        changedFiles = $changed
        changedSql   = $changedSql
        changedCs    = $changedCs
        hasSql       = ($sqlFiles.Count -gt 0)
        hasChanges   = ($changed.Count -gt 0)
    })
}

# --- Standard SQL (every SaaS package) ---
# templates\sql holds objects every client needs, e.g. ckbcustom.cx_log and the
# procs LogWriter calls. Added after the projects so a project's own copy of
# the same object wins (same Get-ObjectName key).
$stdRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\templates\sql')).Path
foreach ($f in @(Get-ChildItem $stdRoot -Recurse -Filter '*.sql' -File | Sort-Object FullName)) {
    $rel = 'kraken-standard/SQL/' + $f.FullName.Substring($stdRoot.Length + 1).Replace('\', '/')
    $key = Get-ObjectName $rel
    if ($seenObjects.ContainsKey($key)) { continue }
    $seenObjects[$key] = $true
    [void]$allSql.Add([PSCustomObject]@{ path = $rel; fullPath = $f.FullName; tier = (Get-Tier $rel); project = 'kraken-standard' })
}

if ($allSql.Count -eq 0) { throw 'No SQL files found for selected projects.' }

# Pre-build file->subject map: one git log call instead of N per-file calls
$fileSubjectMap = @{}
$_gitLog = if ($baseline) { @(git log "$baseline..HEAD" --name-status --pretty=format:"|||%s" 2>$null) } else { @() }
$_curSubj = ''
foreach ($_line in $_gitLog) {
    if ($_line -match '^\|\|\|(.*)') { $_curSubj = $Matches[1].Trim() }
    elseif ($_line -match '^[AMDRC]\t(.+)$') {
        $_fp = $Matches[1].Trim() -replace '\\', '/'
        if (-not $fileSubjectMap.ContainsKey($_fp)) { $fileSubjectMap[$_fp] = $_curSubj }
    }
}

# --- Build manual-deploy-fallback.sql (SSMS fallback; not run by Deploy-SQL.ps1) ---
$objects = [System.Collections.Generic.List[object]]::new()
$allGrants = [System.Collections.Generic.List[string]]::new()
$tierBodies = @{
    -2 = [System.Collections.Generic.List[string]]::new()
    -1 =[System.Collections.Generic.List[string]]::new()
     0 = [System.Collections.Generic.List[string]]::new()
     1 = [System.Collections.Generic.List[string]]::new()
     2 = [System.Collections.Generic.List[string]]::new()
     3 = [System.Collections.Generic.List[string]]::new()
     4 = [System.Collections.Generic.List[string]]::new()
     5 = [System.Collections.Generic.List[string]]::new()
    99 = [System.Collections.Generic.List[string]]::new()
}
$num = 1
$sqlCache = @{}  # path -> parsed result; avoids reading + cleaning each file twice

foreach ($item in ($allSql | Sort-Object tier, path)) {
    $fullPath = if ($item.PSObject.Properties['fullPath']) { $item.fullPath } else { Join-Path $RepoRoot ($item.path -replace '/', '\') }
    $raw = Get-Content -Raw -LiteralPath $fullPath
    $clean = Clean-SqlContent $raw
    $parsed = Extract-Grants $clean
    $sqlCache[$item.path] = $parsed  # cache for batch staging loop
    foreach ($g in $parsed.Grants) { if ($allGrants -notcontains $g) { [void]$allGrants.Add($g) } }

    $note = ($raw -split "`r?`n" | Where-Object {
        $_ -match '^\s*--' -and $_ -notmatch 'Development\s*:|Author\s*:|Date\s*:|Version|M O D I F I C A T I O N S|I N I T I A L|='
    } | Select-Object -First 1)
    if ($note) { $note = ($note -replace '^\s*--\s*', '').Trim() }
    if (-not $note) { $note = $fileSubjectMap[$item.path] }
    if (-not $note) { $note = $item.project }

    $displayName = Get-ObjectName $item.path
    if ($displayName -notmatch '^ckbcustom\.' -and $item.path -match 'Configuration') {
        $displayName = [IO.Path]::GetFileNameWithoutExtension($item.path)
    } elseif ($displayName -match '^ckbcustom\.') {
        $displayName = 'ckbcustom.' + ($displayName -replace '^ckbcustom\.', '')
    }

    [void]$objects.Add([PSCustomObject]@{
        Number = $num
        Name   = $displayName
        Type   = (Get-ObjectType $item.tier)
        Notes  = $note
        Tier   = $item.tier
        Path   = $item.path
        Project = $item.project
    })
    [void]$tierBodies[$item.tier].Add($parsed.Body)
    $num++
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("-- ============================================================")
[void]$sb.AppendLine("-- Deployment: $deployDate")
[void]$sb.AppendLine("-- Target:     $server  |  Database: $database")
[void]$sb.AppendLine("-- Run in:     SSMS -- safe to re-run (all CREATE OR ALTER)")
[void]$sb.AppendLine("-- Mode:       Full SQL install for: $($request.projects -join ', ')")
[void]$sb.AppendLine("-- ============================================================")
foreach ($o in $objects) {
    [void]$sb.AppendLine("-- $($o.Number). $($o.Name)   $($o.Type)   $($o.Notes)")
}
[void]$sb.AppendLine("-- ============================================================")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("USE $database")
[void]$sb.AppendLine("GO")
foreach ($tier in -2, -1, 0, 1, 2, 3, 4, 5) {
    if ($tierBodies[$tier].Count -eq 0) { continue }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("-- --------------------------------------------------------")
    [void]$sb.AppendLine("-- $(Get-TierSection $tier)")
    [void]$sb.AppendLine("-- --------------------------------------------------------")
    [void]$sb.Append(($tierBodies[$tier] -join "`nGO`n`n") + "`nGO`n")
}
if ($tierBodies[99].Count -gt 0) {
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("-- --------------------------------------------------------")
    [void]$sb.AppendLine("-- UNKNOWN (verify ordering manually)")
    [void]$sb.AppendLine("-- --------------------------------------------------------")
    [void]$sb.Append(($tierBodies[99] -join "`nGO`n`n") + "`nGO`n")
}
if ($allGrants.Count -gt 0) {
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("-- --------------------------------------------------------")
    [void]$sb.AppendLine("-- GRANTS")
    [void]$sb.AppendLine("-- --------------------------------------------------------")
    [void]$sb.Append(($allGrants -join "`n") + "`nGO`n")
}
$deploySql = $sb.ToString()

Set-Content -LiteralPath (Join-Path $deployDir 'manual-deploy-fallback.sql') -Value $deploySql -Encoding UTF8

# --- Build README ---
$rsb = [System.Text.StringBuilder]::new()
[void]$rsb.AppendLine("# Release $release - build $build")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("**Tag:** $buildTag")
[void]$rsb.AppendLine("**Packaged:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$rsb.AppendLine("**Baseline (for diffs):** $(if ($baseline) { $baseline } else { 'none - initial package' })")
[void]$rsb.AppendLine("**Projects:** $($request.projects -join ', ')")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("This package is environment-agnostic: deploy the same zips to Test, then Prod.")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("---")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("## Overview")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("Full SQL installation package for **$($request.projects -join '** and **')**. All SQL objects under each project's ``SQL/`` folder are included (CREATE OR ALTER - safe to re-run). Web DLLs are staged from ``bin/`` when present.")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("---")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("## SQL deployment paths")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("This package ships the same SQL in two forms - use **one** path, not both.")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("| Location | Method | When to use |")
[void]$rsb.AppendLine("|----------|--------|-------------|")
[void]$rsb.AppendLine("| ``SQL/001_*.sql`` ... ``SQL/$('{0:D3}' -f $objects.Count)_*.sql`` | **Automated (normal)** - run ``Deploy-SQL.ps1`` on the batch server | Standard SaaS deploy. Backs up first, then runs each file in order. |")
[void]$rsb.AppendLine("| ``manual-deploy-fallback.sql`` (batch zip **root**, not under ``SQL/``) | **Manual (SSMS fallback)** - open in SSMS and execute | Batch automation unavailable, or review the full script before deploy. |")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("**Why ``manual-deploy-fallback.sql`` is at the zip root:** ``Deploy-SQL.ps1`` runs every ``*.sql`` in ``SQL/``. If the combined script were in ``SQL/``, deploy would run all objects twice (numbered files, then the combined script). Root placement keeps automated and manual paths separate.")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("Both paths deploy the same **$($objects.Count)** deduplicated objects (CREATE OR ALTER - safe to re-run).")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("---")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("## Changes Since Baseline")
[void]$rsb.AppendLine("")

if (-not $baseline) {
    [void]$rsb.AppendLine("Initial package - no baseline. Every object is listed under **SQL Files Deployed**.")
} else {
    $anyChanges = $false
    foreach ($pd in $projectData) {
        if ($pd.changedFiles.Count -eq 0) {
            [void]$rsb.AppendLine("`n### $($pd.projectName)`n`nNo file changes since ``$baseline``.`n")
            continue
        }
        $anyChanges = $true
        [void]$rsb.AppendLine("`n### $($pd.projectName)`n")
        if ($pd.changedSql.Count -gt 0) {
            [void]$rsb.AppendLine("**SQL (changed):**")
            foreach ($f in $pd.changedSql) { [void]$rsb.AppendLine("- ``$f``") }
        }
        if ($pd.changedCs.Count -gt 0) {
            [void]$rsb.AppendLine("**C# / web (changed):**")
            foreach ($f in $pd.changedCs) {
                $subj = $fileSubjectMap[$f]
                if ($subj) { [void]$rsb.AppendLine("- ``$f`` - $subj") }
                else { [void]$rsb.AppendLine("- ``$f``") }
            }
        }
        $other = $pd.changedFiles | Where-Object { $_ -notmatch '\.(sql|cs)$' }
        if ($other) {
            [void]$rsb.AppendLine("**Other:**")
            foreach ($f in $other) { [void]$rsb.AppendLine("- ``$f``") }
        }
    }

    if (-not $anyChanges) {
        [void]$rsb.AppendLine("`nNo file changes since ``$baseline`` across selected projects. Package is a full SQL reinstall.")
    }
}

[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("---")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("## SQL Files Deployed (full install)")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("All ``*.sql`` files from each project's ``SQL/`` folder (excluding ``Tests/``, ``Old procs/``). Duplicates across projects (e.g. shared ``cx_job_ins``) are included once in ``manual-deploy-fallback.sql`` and once each in the numbered ``SQL/`` files for batch deploy.")
[void]$rsb.AppendLine("")

foreach ($pd in $projectData) {
    [void]$rsb.AppendLine("")
    [void]$rsb.AppendLine("### $($pd.projectName) ($($pd.sqlFiles.Count) files)")
    [void]$rsb.AppendLine("")
    [void]$rsb.AppendLine("| # | File | Tier | Type |")
    [void]$rsb.AppendLine("|---|------|------|------|")
    $i = 1
    foreach ($s in ($pd.sqlFiles | Sort-Object tier, path)) {
        [void]$rsb.AppendLine("| $i | ``$($s.path)`` | $($s.tier) | $(Get-ObjectType $s.tier) |")
        $i++
    }
}

[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("---")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("## Combined manual-deploy-fallback.sql Objects")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("| # | Object | Type | Source project | Notes |")
[void]$rsb.AppendLine("|---|--------|------|----------------|-------|")
[void]$rsb.AppendLine("")

foreach ($o in $objects) {
    [void]$rsb.AppendLine("| $($o.Number) | ``$($o.Name)`` | $($o.Type) | $($o.Project) | $($o.Notes) |")
}

[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("---")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("## Where things go")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("| Package | Run | Goes to |")
[void]$rsb.AppendLine("|---|---|---|")
[void]$rsb.AppendLine("| ``deploy-batch.zip`` | ``Deploy-SQL.ps1`` | CKB, connection from ``F:\batch\bin\set_env.ps1`` |")
[void]$rsb.AppendLine("| ``deploy-batch.zip`` (if it has ``exe\``) | ``Deploy-Exe.ps1`` | ``$batchTarget\<project>`` unless the project sets ``deployTo`` |")
[void]$rsb.AppendLine("| ``deploy-web.zip`` | ``Deploy-Web.ps1`` | ``$webTarget`` |")
$saproText = if ($saproTarget) { "``$saproTarget`` unless the project sets ``deployTo``" } else { 'by hand (no SA Pro location in client.json)' }
[void]$rsb.AppendLine("| ``deploy-sapro.zip`` (if any) | ``Deploy-SaPro.ps1`` | $saproText |")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("---")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("## Install (one script)")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("Copy this build folder to the batch server, open PowerShell in it and run:")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("``````powershell")
[void]$rsb.AppendLine("powershell -ExecutionPolicy Bypass -File .\Install-Package.ps1")
[void]$rsb.AppendLine("``````")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("It unzips each package into ``batch\``, ``sapro\``, ``web\`` and runs the steps below in order, stopping at the first failure. ``-SkipSql``, ``-SkipExe``, ``-SkipSaPro``, ``-SkipWeb`` leave a step out. The steps below are what it runs, for doing one by hand.")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("## Step 1 -- Run batch package (automated SQL)")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("Unzip ``deploy-batch.zip`` on the batch server into a folder named ``$buildFolder``. Run ``Deploy-SQL.ps1`` as Administrator.")
[void]$rsb.AppendLine("It creates ``ckbcustom.cx_deploy_log`` if missing, logs the run, backs up every object it touches into ``Backup\<time>\``, then runs the numbered files in ``SQL/`` (not ``manual-deploy-fallback.sql``). A failed backup stops before any SQL runs.")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("**To undo:** run ``Backup\<time>\Rollback.ps1``. Roll back newest build first; it refuses if a later build changed the same objects. Tables and table types are not restored.")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("**SSMS fallback (optional):** Instead of Step 1, open ``manual-deploy-fallback.sql`` from the batch zip root in SSMS and execute against **$database** on **$server**. Do not run both paths.")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("## Step 2 -- Run web package")
[void]$rsb.AppendLine("")
[void]$rsb.AppendLine("Unzip ``deploy-web.zip`` on the web server. Run ``Deploy-Web.ps1`` as Administrator.")
[void]$rsb.AppendLine("Target: **$webTarget**")
[void]$rsb.AppendLine("")

$step = 3
foreach ($pd in $projectData) {
    if ($pd.csFiles.Count -eq 0) { continue }
    [void]$rsb.AppendLine("## Step $step -- Build and Deploy: $($pd.projectName)")
    [void]$rsb.AppendLine("")
    [void]$rsb.AppendLine("Build Release; copy DLLs and web assets (or use ``Deploy-Web.ps1`` from package).")
    [void]$rsb.AppendLine("")
    $step++
}

[System.IO.File]::WriteAllText((Join-Path $deployDir 'README.md'), $rsb.ToString(), [System.Text.Encoding]::UTF8)

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
$manifestObjects = New-Object System.Collections.Generic.List[object]
$seq = 1
foreach ($item in ($allSql | Sort-Object tier, path)) {
    $destName = '{0:D3}_{1}' -f $seq, (Split-Path $item.path -Leaf)
    $parsed = $sqlCache[$item.path]
    Set-Content -LiteralPath (Join-Path $stageBatch "SQL\$destName") -Value $parsed.Body -Encoding UTF8 -NoNewline
    Add-Content -LiteralPath (Join-Path $stageBatch "SQL\$destName") -Value "" -Encoding UTF8
    $info = Get-SqlObjectInfo $parsed.Body
    $manifestObjects.Add([PSCustomObject]@{ file = "SQL/$destName"; source = $item.path; name = $info.name; kind = $info.kind; action = $info.action })
    $seq++
}
if ($allGrants.Count -gt 0) {
    $grantSql = ($allGrants | ForEach-Object { if ($_ -notmatch ';$') { $_ + ';' } else { $_ } }) -join "`r`n"
    Set-Content -LiteralPath (Join-Path $stageBatch "SQL\$('{0:D3}_grants.sql' -f $seq)") -Value $grantSql -Encoding UTF8
    $seq++
}
Test-BatchSqlFiles (Join-Path $stageBatch 'SQL')
# Deploy-time scripts are static and read manifest.json: self-contained, no
# dependency on cx_call_sql.ps1 or any other batch-server script.
$tplBatch = Join-Path $PSScriptRoot '..\templates\batch'
foreach ($f in @('Deploy-SQL.ps1', 'Rollback.ps1', 'DeployLib.ps1', 'cx_deploy_log.sql')) {
    Copy-Item (Join-Path $tplBatch $f) $stageBatch -Force
}
# manifest.json drives Deploy-SQL.ps1 (what to back up), the release README
# and the deploy log. Repo state excludes the package itself.
$dirty = [bool](git status --porcelain -- . ':(exclude)Deployments' ':(exclude)_package-request.json' ':(exclude)_package-build.json' 2>$null)
$manifest = [ordered]@{
    release     = $release
    build       = $build
    buildFolder = $buildFolder
    tag         = $buildTag
    commit      = [string](git rev-parse HEAD 2>$null)
    dirty       = $dirty
    baseline    = $baseline
    createdAt   = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    projects    = @($request.projects)
    targets     = [ordered]@{ web = $webTarget; batch = $batchTarget; sapro = $saproTarget }
    objects     = $manifestObjects.ToArray()
    files       = @(Get-ChildItem (Join-Path $stageBatch 'SQL') -Filter '*.sql' | Sort-Object Name | ForEach-Object {
                      [ordered]@{ path = "SQL/$($_.Name)"; sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash } })
}
$manifestJson = ConvertTo-Json -InputObject $manifest -Depth 5
Set-Content (Join-Path $deployDir 'manifest.json') $manifestJson -Encoding UTF8
Set-Content (Join-Path $stageBatch 'manifest.json') $manifestJson -Encoding UTF8

# One commented entry point for the whole build: unzips each zip, then runs
# Deploy-SQL / Deploy-Exe / Deploy-SaPro / Deploy-Web in order. Sits next to the
# zips, not inside one, so it is the first thing seen in the build folder.
Copy-Item (Join-Path $PSScriptRoot '..\templates\Install-Package.ps1') $deployDir -Force

Copy-Item (Join-Path $deployDir 'README.md') $stageBatch -Force
Copy-Item (Join-Path $deployDir 'manual-deploy-fallback.sql') $stageBatch -Force

# Manual Scripts: copy from each project's SQL/Manual Scripts/ (or SQL/Manual/) into stage-batch/Manual Scripts/
# These are reference/run-manually scripts -- included in the ZIP for human use, NOT run by Deploy-SQL.ps1
foreach ($proj in $request.projects) {
    foreach ($manualDir in @('Manual Scripts', 'Manual')) {
        $src = Join-Path $projRoots[$proj] "SQL\$manualDir"
        if (Test-Path $src) {
            $dest = Join-Path $stageBatch 'Manual Scripts'
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Copy-Item "$src\*" $dest -Recurse -Force
            Write-Host "  Staged Manual Scripts from $proj\SQL\$manualDir"
        }
    }
}

# Web: stage from each project's bin/Views/CSS/JS if present (Release preferred; no pdb/vshost)
$webStaged = $false
foreach ($proj in $request.projects) {
    $root = $projRoots[$proj]
    # A project client.json marks batch, SA Pro or skip has no web files.
    $cp = Get-ClientProject $clientCfg $proj
    if ($cp -and $cp.target -and $cp.target -ne 'web') { continue }
    $webStaged = $true
    $releaseBin = Join-Path $root 'bin\Release'
    $binDirs = if (Test-Path $releaseBin) { @($releaseBin) } else { @((Join-Path $root 'bin')) }
    foreach ($bd in $binDirs) {
        if (-not (Test-Path $bd)) { continue }
        Get-ChildItem $bd -Filter '*.dll' -ErrorAction SilentlyContinue |
            Where-Object { Test-WebDll $_.Name $clientCfg.webDlls $clientCfg.vendorWebDlls } |
            Copy-Item -Destination "$wf\bin\" -Force -ErrorAction SilentlyContinue
        Get-ChildItem $bd -Filter '*.dll.config' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^(CX\.|Cantactix\.OpenAccess\.Automator)\.dll\.config$' -and
                (Get-Content $_.FullName -Raw) -notmatch 'Serilog'
            } |
            Copy-Item -Destination "$wf/bin\" -Force -ErrorAction SilentlyContinue
    }
    # Vendor DLLs OA does not ship: build output first, else Libraries.
    foreach ($v in $clientCfg.vendorWebDlls) {
        $src = Find-VendorDll $root $v
        if ($src) { Copy-Item $src "$wf\bin\" -Force }
    }
    foreach ($sub in @('Views', 'CSS', 'Css', 'Styles', 'Javascript', 'JavaScript', 'Images', 'Templates')) {
        $p = Join-Path $root $sub
        if (-not (Test-Path $p)) { continue }
        switch ($sub) {
            'Views' { Copy-Item "$p\*.ascx" "$wf\Custom\" -Force -ErrorAction SilentlyContinue; Copy-Item "$p\..\HelperClasses\*.ashx" "$wf\Custom\" -Force -ErrorAction SilentlyContinue; Copy-Item "$p\..\HelperClasses\*.aspx" "$wf\Custom\" -Force -ErrorAction SilentlyContinue }
            { $_ -in 'CSS', 'Css', 'Styles' } { Copy-Item "$p\*.css" "$wf\Custom\Styles\" -Force -ErrorAction SilentlyContinue }
            { $_ -in 'Javascript', 'JavaScript' } { Copy-Item "$p\*.js" "$wf\Custom\scripts\" -Force -ErrorAction SilentlyContinue }
            'Images' { Copy-Item "$p\*" "$wf\Images\" -Force -ErrorAction SilentlyContinue }
            'Templates' { Copy-Item "$p\*" "$wf\Custom\Templates\" -Force -ErrorAction SilentlyContinue }
        }
    }
    $cfg = Join-Path $root 'Config\CrispCustomizations.config'
    if (-not (Test-Path $cfg)) { $cfg = Join-Path $RepoRoot 'Config\CrispCustomizations.config' }
    if (Test-Path $cfg) { Copy-Item $cfg "$wf\Custom\Config\" -Force }
}
# A vendor DLL named in client.json must ship; the built-in list is best effort.
if ($webStaged -and $clientCfg.vendorExplicit) {
    foreach ($v in $clientCfg.vendorWebDlls) {
        if (-not (Test-Path (Join-Path "$wf\bin" $v))) { throw "Vendor DLL $v (client.json vendorWebDlls) not found in any web project's bin or Libraries folder." }
    }
}

Copy-Item (Join-Path $deployDir 'README.md') $stageWeb -Force

$deployWebPs1 = @"
# Deploy-Web.ps1 - release $release build $build
param([string]`$WebTarget = "$webTarget")
Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$webFiles  = Join-Path `$scriptDir "WebFiles"
if (-not (Test-Path `$webFiles)) { Write-Host "ERROR: WebFiles not found"; exit 1 }
Write-Host "--- Web deployment -> `$WebTarget ---"
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

# --- EXE staging: console apps -> stage-batch\exe\ ---
$stageExe = Join-Path $stageBatch 'exe'
$exeProjectsStaged = @()
foreach ($proj in $request.projects) {
    $csproj = Get-ChildItem $projRoots[$proj] -Filter '*.csproj' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $csproj) { continue }
    $projXml = [xml](Get-Content $csproj.FullName -Raw)
    $outputType = $projXml.Project.PropertyGroup | Where-Object { $_.OutputType } | Select-Object -First 1 | ForEach-Object { $_.OutputType }
    if ($outputType -ne 'Exe') { continue }
    $csFiles2 = Get-ChildItem $projRoots[$proj] -Filter '*.cs' -Recurse -ErrorAction SilentlyContinue
    if (-not $csFiles2) { continue }
    $releaseBin = Join-Path $projRoots[$proj] 'bin\Release'
    if (-not (Test-Path $releaseBin)) { Write-Warning "  No Release bin for $proj -- EXE not staged"; continue }
    $projExeDir = Join-Path $stageExe $proj
    New-Item -ItemType Directory -Path $projExeDir -Force | Out-Null
    # Stage EXE + config
    Get-ChildItem $releaseBin -Filter '*.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.vshost\.' } |
        Copy-Item -Destination $projExeDir -Force
    Get-ChildItem $releaseBin -Filter '*.exe.config' -ErrorAction SilentlyContinue |
        Copy-Item -Destination $projExeDir -Force
    # Stage non-framework DLL dependencies.
    #
    # The prefix filter assumes a System.* or Microsoft.* name means the
    # framework provides it. That is not always true: a project referencing a
    # netstandard2.0 library binds the NuGet *package* identity of these
    # assemblies, not the framework one, so the file next to the exe is a real
    # dependency. Dropping it produces an exe that starts and then throws
    # FileNotFoundException on first use -- e.g. System.Data.SqlClient
    # 4.6.1.6 at the first query -- which looks like a database problem rather
    # than a packaging one.
    #
    # So: keep the prefix filter, but exempt the ones that actually ship
    # alongside an exe. Extend this list rather than widening the filter; the
    # point of the filter is to keep genuinely framework-provided assemblies
    # out of the package.
    $packageDllExemptions = @(
        'System.Data.SqlClient.dll',
        'System.Buffers.dll',
        'System.Memory.dll',
        'System.Numerics.Vectors.dll',
        'System.Runtime.CompilerServices.Unsafe.dll',
        'System.Threading.Tasks.Extensions.dll',
        'System.ValueTuple.dll',
        'System.Text.Json.dll',
        'System.Text.Encodings.Web.dll',
        'Microsoft.Bcl.AsyncInterfaces.dll'
    )

    Get-ChildItem $releaseBin -Filter '*.dll' -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -notmatch '^(Microsoft\.|System\.|mscorlib|Newtonsoft\.Json)' -or
            $packageDllExemptions -contains $_.Name
        } |
        Copy-Item -Destination $projExeDir -Force
    Write-Output "  Staged EXE: $proj"
    $exeProjectsStaged += $proj
}

if ($exeProjectsStaged.Count -gt 0) {
    # Projects with their own location (client.json deployTo).
    $exeOverrides = @($exeProjectsStaged | ForEach-Object {
        $p = Get-ClientProject $clientCfg $_
        if ($p -and $p.PSObject.Properties['deployTo'] -and $p.deployTo) { "    '$_' = '$($p.deployTo)'" }
    }) -join "`r`n"
    $deployExePs1 = @"
# Deploy-Exe.ps1 - release $release build $build
param([string]`$ExeTarget = "$batchTarget")
Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$exeDir    = Join-Path `$scriptDir "exe"
`$overrides = @{
$exeOverrides
}
if (-not (Test-Path `$exeDir)) { Write-Host "ERROR: exe folder not found"; exit 1 }
Write-Host "--- EXE deployment -> `$ExeTarget ---"
Get-ChildItem `$exeDir -Directory | ForEach-Object {
    `$dest = if (`$overrides.ContainsKey(`$_.Name)) { `$overrides[`$_.Name] } else { Join-Path `$ExeTarget `$_.Name }
    if (-not (Test-Path `$dest)) { New-Item -ItemType Directory -Force `$dest | Out-Null }
    Get-ChildItem `$_.FullName -File | ForEach-Object {
        Copy-Item `$_.FullName `$dest -Force
        Write-Host "  `$(`$_.Name) -> `$dest"
    }
}
Write-Host "--- EXE deployment complete ---"
"@
    Set-Content -LiteralPath (Join-Path $stageBatch 'Deploy-Exe.ps1') -Value $deployExePs1 -Encoding ASCII
}

# --- SA Pro staging: Space Automation scripts -> stage-sapro\ (flat) ---
# SA Pro scripts go to the client's Space Automation script directory. When
# client.json sets targets.sapro the zip ships Deploy-SaPro.ps1 defaulting to
# it; otherwise it names no target and the files are copied by hand. SQL stays
# in the batch package -- the DB credentials only exist on the batch server.
$stageSaPro = Join-Path $deployDir 'stage-sapro'
$saProStaged = @()
foreach ($proj in $request.projects) {
    $csproj = Get-ChildItem $projRoots[$proj] -Filter '*.csproj' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $csproj) { continue }
    $csprojText = Get-Content $csproj.FullName -Raw
    # Same marker the deployment portal classifies on.
    if ($csprojText -notmatch 'JDA\.Intactix\.Automation') { continue }

    $projXml = [xml]$csprojText
    $asmName = $projXml.Project.PropertyGroup | Where-Object { $_.AssemblyName } | Select-Object -First 1 | ForEach-Object { $_.AssemblyName }
    if (-not $asmName) { $asmName = [IO.Path]::GetFileNameWithoutExtension($csproj.Name) }

    $releaseBin = Join-Path $projRoots[$proj] 'bin\Release'
    if (-not (Test-Path $releaseBin)) { Write-Warning "  No Release bin for $proj -- SA Pro script not staged"; continue }

    $dll = Join-Path $releaseBin "$asmName.dll"
    if (-not (Test-Path $dll)) { Write-Warning "  $asmName.dll not found in $proj\bin\Release -- not staged"; continue }

    if (-not (Test-Path $stageSaPro)) { New-Item -ItemType Directory -Path $stageSaPro -Force | Out-Null }

    # Flat layout: every SA Pro DLL name in the repo is unique. Copy the BUILT
    # config, never the source App.config -- every project names that file
    # identically, so copying source would collapse them all into one.
    Copy-Item $dll $stageSaPro -Force
    $cfg = Join-Path $releaseBin "$asmName.dll.config"
    if (Test-Path $cfg) { Copy-Item $cfg $stageSaPro -Force }

    Write-Output "  Staged SA Pro: $proj -> $asmName.dll"
    $saProStaged += [PSCustomObject]@{ project = $proj; assembly = $asmName; hasConfig = (Test-Path $cfg) }
}

if ($saProStaged.Count -gt 0) {
    $ssb = New-Object System.Text.StringBuilder
    [void]$ssb.AppendLine("# SA Pro scripts -- release $release build $build")
    [void]$ssb.AppendLine("")
    if ($saproTarget) {
        [void]$ssb.AppendLine("$($saProStaged.Count) Space Automation Pro script(s). Run ``Deploy-SaPro.ps1``: it copies them to")
        [void]$ssb.AppendLine("``$saproTarget`` (or a project's ``deployTo``). Pass ``-SaProTarget`` to override.")
    } else {
        [void]$ssb.AppendLine("$($saProStaged.Count) Space Automation Pro script(s). These are **user-deployed**: copy the")
        [void]$ssb.AppendLine("files below into the Space Automation script directory for this client.")
        [void]$ssb.AppendLine("")
        [void]$ssb.AppendLine("No SA Pro location is set in client.json (targets.sapro), so none is recorded here.")
    }
    [void]$ssb.AppendLine("")
    [void]$ssb.AppendLine("**SQL for these scripts is in ``deploy-batch.zip``, not here.** It runs once on the")
    [void]$ssb.AppendLine("batch server via ``Deploy-SQL.ps1`` along with all other SQL in this release.")
    [void]$ssb.AppendLine("")
    [void]$ssb.AppendLine("| File | Source project | Config |")
    [void]$ssb.AppendLine("|---|---|---|")
    foreach ($e in ($saProStaged | Sort-Object assembly)) {
        $cfgCell = if ($e.hasConfig) { "``$($e.assembly).dll.config``" } else { "none" }
        [void]$ssb.AppendLine("| ``$($e.assembly).dll`` | $($e.project) | $cfgCell |")
    }
    Set-Content -LiteralPath (Join-Path $stageSaPro 'README-SAPRO.md') -Value $ssb.ToString() -Encoding UTF8
    if ($saproTarget) {
        $saproOverrides = @($saProStaged | ForEach-Object {
            $p = Get-ClientProject $clientCfg $_.project
            if ($p -and $p.PSObject.Properties['deployTo'] -and $p.deployTo) { "    '$($_.assembly)' = '$($p.deployTo)'" }
        }) -join "`r`n"
        $deploySaProPs1 = @"
# Deploy-SaPro.ps1 - release $release build $build
param([string]`$SaProTarget = "$saproTarget")
Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$overrides = @{
$saproOverrides
}
Write-Host "--- SA Pro deployment -> `$SaProTarget ---"
Get-ChildItem `$scriptDir -File | Where-Object { `$_.Name -match '\.dll(\.config)?`$' } | ForEach-Object {
    `$asm = `$_.Name -replace '\.dll(\.config)?`$', ''
    `$dest = if (`$overrides.ContainsKey(`$asm)) { `$overrides[`$asm] } else { `$SaProTarget }
    if (-not (Test-Path `$dest)) { New-Item -ItemType Directory -Force `$dest | Out-Null }
    Copy-Item `$_.FullName `$dest -Force
    Write-Host "  `$(`$_.Name) -> `$dest"
}
Write-Host "--- SA Pro deployment complete ---"
"@
        Set-Content -LiteralPath (Join-Path $stageSaPro 'Deploy-SaPro.ps1') -Value $deploySaProPs1 -Encoding ASCII
    }
    Write-Output "SA Pro: staged $($saProStaged.Count) script(s) to stage-sapro"
}

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
if (Test-Path $stageSaPro) {
    Compress-Archive -Path "$stageSaPro\*" -DestinationPath (Join-Path $deployDir 'deploy-sapro.zip') -Force
}

Complete-BuildStamp $RepoRoot $packageBuild
Invoke-PostPackageCleanup -deployDir $deployDir -repoRoot $RepoRoot

Write-Output "deploy-web.zip: $(Join-Path $deployDir 'deploy-web.zip')"
Write-Output "deploy-batch.zip: $(Join-Path $deployDir 'deploy-batch.zip')"
Write-Output "Batch SQL files: $($seq - 1)"
Write-Output "Kept in $deployDir : README.md, manual-deploy-fallback.sql, deploy-*.zip, component guides (*.md, *.xlsx)"
