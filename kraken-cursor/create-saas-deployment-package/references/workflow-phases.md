# Workflow phases — kraken-cursor-create-saas-deployment-package

Parent agent: execute phases in order. Launch parallel Task subagents in a **single message** when marked PARALLEL.

Task settings: `subagent_type: generalPurpose`, `model` optional, pass the full prompt below as `prompt`.

---

## Phase 1: Coordinate

**Single Task or parent executes directly.**

```
You are the Coordinate agent for the deployment package builder.

Repo root: {repoRoot}
Flag: {flag}

Steps:
1. Read `{repoRoot}/_package-request.json`.
   Extract: projects (string array), environment (string), baseline (string or null), deployType (string),
   webTarget (string, default "U:\\OpenAccess\\Customization\\"), batchTarget (string, default "F:\\batch\\exe").
2. Read `{repoRoot}/Environment Details/env-config.json`.
   Look up server and database for the key matching the environment value from step 1.
3. Resolve baseline:
   - If baseline is a non-null, non-empty string in _package-request.json, use it directly.
   - If null or missing, run from {repoRoot}:
     git tag --list "deploy/<environment>/*" --sort=-version:refname
     Take the first result (most recent).
   - If still nothing, stop and report: "No deploy tag found for <environment>. Set baseline in _package-request.json manually."
4. Get today's date in YYYY-MM-DD: powershell -Command "Get-Date -Format yyyy-MM-dd"
5. Collect commit messages since baseline (from {repoRoot}):
   git log <baseline>..HEAD --pretty="%s"
6. Return JSON with keys: baseline, environment, date, flag, server, database, projects, commitMessages, webTarget, batchTarget.

Write the JSON to {repoRoot}/.kraken-cursor/deploy-state-working.json under key "coordination".
Return the JSON in your response.
```

---

## Phase 2: Gather (PARALLEL — one Task per project in coordination.projects)

```
You are the Gather agent for project "{projectName}".

Repo root: {repoRoot}
Baseline: {baseline from coordination}

Steps:
1. From {repoRoot}, run:
   git diff --name-only {baseline} HEAD -- {projectName}/
   Also include uncommitted changes:
   git diff --name-only {baseline} -- {projectName}/
   Merge and dedupe file lists.

2. Partition results:

   SQL files: any .sql file. Assign tier:
   - Tier 1 (Tables): path contains "Tables/" AND filename does NOT start with "Populate"
   - Tier 2 (Data): filename starts with "Populate" or "ckbcustom.Populate"
   - Tier 3 (Functions): path contains "Functions/"
   - Tier 4 (Views): path contains "Views/"
   - Tier 5 (Stored Procedures): path contains "Stored Procedures/" OR "Store Procedures/" OR "Procedures/"
   - Tier 99 (Unknown): anything not matching tiers 1-5

   C# files: any .cs file.

   Ignore: .md, .csproj, .sqlproj, .sln, .json, .ps1, .html, Tests/, Old procs/, Deployments/, docs/, .claude/

3. projectRoot = "{projectName}/" (trailing slash)
4. hasChanges = true if any SQL or C# files, else false.
5. Return JSON: { projectName, projectRoot, sqlFiles: [{path, tier}], csFiles: [{path}], hasChanges }
```

Parent merges all Gather results into `changedProjects` = those with hasChanges=true. Write to state file. If empty, stop.

---

## Phase 3: Build (PARALLEL — 2 Tasks)

### 3a SQL Builder

```
You are the SQL Builder agent.

Repo root: {repoRoot}
Deploy date: {deployDate}
Target server: {server}
Target database: {database}

Changed projects:
{changedProjects JSON — name + sqlFiles only}

Steps:
1. Collect ALL sqlFiles across changed projects. Sort: tier asc (1,2,3,4,5,99), then path asc.
2. Deduplicate by object name (e.g. cx_job_ins appearing in two projects — keep one).
3. Read each file from {repoRoot}/<path>.
4. Strip from each file before concatenating:
   - USE <db> followed by standalone GO
   - Leading/trailing standalone GO lines
   - Extract GRANT statements to a separate grants section at end
5. Build header comment list: number, objectName (ckbcustom. prefix if missing), type, notes.
6. Write {repoRoot}/Deployments/{deployDate}/deploy.sql:

-- ============================================================
-- Deployment: {deployDate}
-- Target:     {server}  |  Database: {database}
-- Run in:     SSMS -- safe to re-run (all CREATE OR ALTER)
-- ============================================================
-- 1. ...
-- ============================================================

USE {database}
GO

-- TABLES / DATA / FUNCTIONS / VIEWS / STORED PROCEDURES sections (omit empty)
-- GRANTS section at end if any

Return: "SQL script written with N objects"
```

### 3b README Builder

```
You are the README Builder agent.

Repo root: {repoRoot}
Deploy date: {deployDate}
Server: {server} | Database: {database}
Flag: {flag}
Commit messages: {commitMessages}
Changed projects: {changedProjects JSON}

Steps:
1. Overview paragraph (2-3 sentences). If tier-1 table changed, note backup warning.
2. Step 1 block:
   --saas: Unzip deploy-web.zip + deploy-batch.zip; Deploy-SQL.ps1 on batch; Deploy-Web.ps1 on web server.
   --local: Portal deploy button per project.
3. SQL object table matching deploy.sql order.
4. For each project with csFiles: "## Step N -- Build and Deploy: {ProjectName}" with file list and git log subjects.
5. Write {repoRoot}/Deployments/{deployDate}/README.md
Return: "README written"
```

---

## Phase 4: Commit (optional — only if user requested commit)

```
You are the Commit agent.

Repo root: {repoRoot}
Deploy date: {deployDate}
Environment: {environment}

From {repoRoot}:
1. git add Deployments/{deployDate}/
2. git commit -m "Add {deployDate} deployment package"
3. git tag deploy/{environment}/{deployDate}
4. Upsert deploy-state.json for {environment}
5. git add deploy-state.json && git commit -m "chore: update deploy-state for {environment} {deployDate}"

Do NOT push unless user explicitly asked to push.
Return tag name.
```

---

## Phase 5: Guides (PARALLEL — one Task per changed project + Excel)

Template path: {TEMPLATE_PATH}

### 5a Component guide (per project)

```
You are the Guide agent for "{projectName}".

Repo root: {repoRoot}
Deploy date: {deployDate}
Baseline: {baseline}
Template: {TEMPLATE_PATH}
Project data: {project gather JSON}
Server: {server} | Database: {database}

1. Read template. Replace {{component_name}}, {{date}}, {{brief_description}}, {{implementation_steps}}, {{code_drop}}, {{rollback_steps}}, {{business_justification}} (blank).
2. brief_description: git log {baseline}..HEAD --pretty="%s" -- {projectRoot} | first line, format "{projectName}: <subject>"
3. Write {repoRoot}/Deployments/{deployDate}/{projectName}.md (spaces in name → hyphens)
Return: "Guide written: {projectName}.md"
```

### 5b Excel guide

```
You are the Excel Guide agent.

Repo root: {repoRoot}
Deploy date: {deployDate}
Changed projects: {changedProjects}

For each project compute BriefDescription, ImplementSteps, RollbackSteps, CodeDrop (same logic as guides).
Run PowerShell Excel COM script to write:
{repoRoot}/Deployments/{deployDate}/Deployment Guide.xlsx

If Excel COM fails, report warning and continue.
Return: path or warning.
```

(See Claude workflow.js lines 400-453 for full Excel PowerShell script template.)

---

## Phase 6: Package (--saas)

**Single Task or parent + Shell.**

```
You are the Package agent.

Repo root: {repoRoot}
Deploy date: {deployDate}
Environment: {environment}
Flag: {flag}
webTarget: {webTarget}
changedProjects: {changedProjects}

=== STEP 1: Stage web (stage-web/) ===
Create stage-web/WebFiles/{bin,Custom,Custom/Config,Custom/Styles,Custom/scripts,Images}
For each changed project with csFiles, copy from {projectRoot}bin/Release/ and Views/ etc. per workflow.
Write stage-web/Deploy-Web.ps1 (param WebTarget, copies WebFiles to target).
Copy README.md to stage-web/.

=== STEP 2: Stage batch (stage-batch/) ===
Create stage-batch/SQL/
Copy each SQL file as NN_filename.sql (tier sort order).
Copy *.md guides + README to stage-batch/.
Write stage-batch/Deploy-SQL.ps1 (runs cx_call_sql.ps1 per file in SQL/).

=== STEP 3: ZIPs ===
Compress stage-web/* → Deployments/{deployDate}/deploy-web.zip
Compress stage-batch/* → Deployments/{deployDate}/deploy-batch.zip

=== STEP 4: Commit (only if user asked) ===
git add Deployments/{deployDate}/
git commit -m "Add deployment guides and package for {deployDate}"

Report full paths to both ZIPs.
```

### --local variant

Stage guides only, commit if asked, report tag. No ZIP creation.

---

## Deploy-Web.ps1 template (--saas)

```powershell
# Deploy-Web.ps1 - {environment} deployment {deployDate}
param([string]$WebTarget = "{webTarget}")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$webFiles  = Join-Path $scriptDir "WebFiles"
if (-not (Test-Path $webFiles)) { Write-Host "ERROR: WebFiles not found"; exit 1 }
Write-Host "--- Web deployment {deployDate} -> $WebTarget ---"
$dirs = @("Custom","Custom\Config","Custom/Styles","Custom/scripts","bin","Images")
foreach ($d in $dirs) { $t = Join-Path $WebTarget $d; if (-not (Test-Path $t)) { New-Item -ItemType Directory -Force $t | Out-Null } }
Copy-Item "$webFiles\Custom\*.ascx"     (Join-Path $WebTarget "Custom")         -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\Custom\Config\*"   (Join-Path $WebTarget "Custom\Config")  -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\Custom\Styles\*"   (Join-Path $WebTarget "Custom/Styles")  -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\Custom\scripts\*"  (Join-Path $WebTarget "Custom/scripts") -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\bin\*"             (Join-Path $WebTarget "bin")             -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\Images\*"          (Join-Path $WebTarget "Images")          -Force -ErrorAction SilentlyContinue
Write-Host "--- Web deployment complete ---"
```

## Deploy-SQL.ps1 template (--saas)

```powershell
# Deploy-SQL.ps1 - {environment} deployment {deployDate}
param([string]$LogDir = "F:\batch\log")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Write-Host "--- SQL deployment {deployDate} starting ---"
. "F:\batch\bin\set_env.ps1"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlDir    = Join-Path $scriptDir "SQL"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force $LogDir | Out-Null }
$files = Get-ChildItem "$sqlDir\*.sql" | Sort-Object Name
$i = 0; $total = $files.Count
foreach ($file in $files) {
    $i++; $scriptName = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    Write-Host "[$i/$total] $($file.Name)"
    & "F:\batch\bin\cx_call_sql.ps1" -scriptName $scriptName -sqlScript $file.FullName -logDir $LogDir -dbServer $env:DBSOURCECKB -dbName $env:DBNAMECKB -dbUser $env:DBUSER -dbPwd $env:DBPWD
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED exit $LASTEXITCODE"; exit $LASTEXITCODE }
}
Write-Host "--- SQL deployment complete ($total files) ---"
```
