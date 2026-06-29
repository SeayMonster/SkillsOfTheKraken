export const meta = {
  name: 'create-saas-deployment-package',
  description: 'Multi-agent deployment package builder: full SQL install, diff-aware README, guides, ZIPs',
  phases: [
    { title: 'Coordinate', detail: 'Resolve baseline, env, server/db from _package-request.json and env-config.json' },
    { title: 'Gather', detail: 'One agent per project: full SQL inventory + baseline diff for README' },
    { title: 'Build', detail: 'SQL Builder + README Builder in parallel' },
    { title: 'Commit', detail: 'git commit + tag + deploy-state.json' },
    { title: 'Guides', detail: 'One guide agent per project + Excel agent in parallel' },
    { title: 'Package', detail: 'deploy-web.zip + deploy-batch.zip (--saas) or push only (--local)' },
  ],
}

const flag = (args && args.flag) || '--saas'
const repoRoot = (args && args.repoRoot) || 'C:\\Users\\bseay\\source\\repos\\Academy'

const COORDINATION_SCHEMA = {
  type: 'object',
  required: ['baseline', 'environment', 'date', 'flag', 'server', 'database', 'projects', 'commitMessages'],
  properties: {
    baseline:       { type: 'string' },
    environment:    { type: 'string' },
    date:           { type: 'string' },
    flag:           { type: 'string' },
    server:         { type: 'string' },
    database:       { type: 'string' },
    projects:       { type: 'array', items: { type: 'string' } },
    commitMessages: { type: 'array', items: { type: 'string' } },
    webTarget:      { type: 'string' },
    batchTarget:    { type: 'string' },
  },
}

const PROJECT_GATHER_SCHEMA = {
  type: 'object',
  required: ['projectName', 'projectRoot', 'sqlFiles', 'csFiles', 'hasChanges', 'hasSql'],
  properties: {
    projectName: { type: 'string' },
    projectRoot: { type: 'string' },
    sqlFiles: {
      type: 'array',
      items: {
        type: 'object',
        required: ['path', 'tier'],
        properties: {
          path: { type: 'string' },
          tier: { type: 'number' },
        },
      },
    },
    csFiles: {
      type: 'array',
      items: {
        type: 'object',
        required: ['path'],
        properties: { path: { type: 'string' } },
      },
    },
    changedFiles: { type: 'array', items: { type: 'string' } },
    changedSql: { type: 'array', items: { type: 'string' } },
    changedCs: { type: 'array', items: { type: 'string' } },
    hasSql: { type: 'boolean' },
    hasChanges: { type: 'boolean' },
  },
}

// --- Phase 1a: Coordinate ---

phase('Coordinate')

const coordination = await agent(
  `You are the Coordinate agent for the deployment package builder.

Repo root: ${repoRoot}
Flag: ${flag}

Steps:
1. Read \`${repoRoot}/_package-request.json\`.
   Extract: projects (string array), environment (string), baseline (string or null), deployType (string),
   webTarget (string, default "U:\\OpenAccess\\Customization\\"), batchTarget (string, default "F:\\batch\\exe").
2. Read \`${repoRoot}/Environment Details/env-config.json\`.
   Look up server and database for the key matching the environment value from step 1.
3. Resolve baseline:
   - If baseline is a non-null, non-empty string in _package-request.json, use it directly.
   - If null or missing, run from ${repoRoot}:
     git tag --list "deploy/<environment>/*" --sort=-version:refname | head -1
   - If still nothing, stop and report: "No deploy tag found for <environment>. Set baseline in _package-request.json manually."
4. Get today's date in YYYY-MM-DD format by running: powershell -Command "Get-Date -Format yyyy-MM-dd"
5. Collect commit messages since baseline (run from ${repoRoot}):
   git log <baseline>..HEAD --pretty="%s"
6. Return structured output with all required fields including webTarget and batchTarget.`,
  { phase: 'Coordinate', schema: COORDINATION_SCHEMA, label: 'coordinate' }
)

if (!coordination) throw new Error('Coordinate agent failed — check _package-request.json and env-config.json.')

log(`Baseline: ${coordination.baseline} | Env: ${coordination.environment} | Date: ${coordination.date}`)

// --- Phase 1b: Gather (parallel, one per project) ---

phase('Gather')

const gatherResults = await parallel(
  coordination.projects.map(projectName => () =>
    agent(
      `You are the Gather agent for project "${projectName}".

Repo root: ${repoRoot}
Baseline: ${coordination.baseline}

Steps:

### A. Full SQL inventory (ALWAYS — new install assumption)

Scan \`${repoRoot}/${projectName}/SQL/\` recursively for all \`*.sql\` files.
Exclude paths containing: Tests/, Old procs/, .vs/
Exclude zero-byte files.

Assign tier to each SQL file:
- Tier 1 (Tables): path contains "Tables/" AND filename does NOT start with "Populate"
- Tier 2 (Data): filename starts with "Populate" or "ckbcustom.Populate"
- Tier 3 (Functions): path contains "Functions/"
- Tier 4 (Views): path contains "Views/"
- Tier 5 (Stored Procedures): path contains "Stored Procedures/" OR "Store Procedures/" OR "Procedures/"
- Tier 99: anything else (Types, Configuration, etc.)

Return ALL matching files in sqlFiles — NOT filtered by git diff.

### B. Changed files since baseline (for README diff section)

Run from ${repoRoot}:
  git diff --name-only ${coordination.baseline} HEAD -- ${projectName}/
  git diff --name-only ${coordination.baseline} -- ${projectName}/
Merge and dedupe into changedFiles.

Partition changedFiles into changedSql (.sql), changedCs (.cs), changedOther.
Ignore in changedFiles: .md, .csproj, .sqlproj, .sln, .json, .ps1, .html, Tests/, Old procs/, Deployments/, docs/, .claude/

csFiles = changedCs as [{path}] (for web deploy steps).

### C. Return structured output

projectRoot = "${projectName}/"
hasSql = sqlFiles.length > 0
hasChanges = changedFiles.length > 0`,
      { phase: 'Gather', schema: PROJECT_GATHER_SCHEMA, label: `gather:${projectName}` }
    )
  )
)

const gathered = gatherResults.filter(Boolean)
const deployProjects = gathered.filter(g => g.hasSql)
const changedProjects = gathered.filter(g => g.hasChanges)

log(`${deployProjects.length}/${coordination.projects.length} projects with SQL | ${changedProjects.length} with baseline changes`)

if (deployProjects.length === 0) {
  log('No SQL files found for selected projects. Stopping.')
  return { status: 'no-sql', baseline: coordination.baseline }
}

const deployDate = coordination.date

// --- Phase 2: Build (SQL Builder + README Builder in parallel) ---

phase('Build')

await parallel([
  () => agent(
    `You are the SQL Builder agent.

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Target server: ${coordination.server}
Target database: ${coordination.database}

Changed projects with SQL files (full install):
${JSON.stringify(deployProjects.map(p => ({ name: p.projectName, sqlFiles: p.sqlFiles })), null, 2)}

Steps:
1. Collect ALL sqlFiles across all deploy projects into one list.
   Sort: by tier ascending (1 then 2 then 3 then 4 then 5 then 99), then alphabetically by path within each tier.
   Deduplicate by object name (lowercase) — shared procs like cx_job_ins appear once.
2. For each SQL file, read its full contents from ${repoRoot}/<path>.
3. Before concatenating, strip from each file's contents:
   - Any line that is exactly "USE <anything>" followed by a standalone "GO"
   - Any leading standalone "GO" lines at the very top
   - Any trailing standalone "GO" lines at the very bottom
4. Build an ordered object list (used in the script header). For each SQL file:
   - number: sequential (1, 2, 3...)
   - objectName: filename without extension, prefixed with "ckbcustom." if not already
   - type: Tables / Data / Function / View / Stored Procedure / Unknown
   - notes: first non-empty line from the file's leading -- comment block that is NOT
     one of: "-- Development :", "-- Author :", "-- Date :", "-- Version"
     If no qualifying comment line exists, run: git log -1 --pretty=%s -- <file> (from ${repoRoot})
5. Create the directory ${repoRoot}/Deployments/${deployDate}/ if it does not exist.
6. Write ${repoRoot}/Deployments/${deployDate}/deploy.sql with this structure:

-- ============================================================
-- Deployment: ${deployDate}
-- Target:     ${coordination.server}  |  Database: ${coordination.database}
-- Run in:     SSMS -- safe to re-run (all CREATE OR ALTER)
-- ============================================================
-- 1. ckbcustom.<object>   <type>   <notes>
-- 2. ...
-- ============================================================

USE ${coordination.database}
GO

-- --------------------------------------------------------
-- TABLES
-- --------------------------------------------------------
<tier-1 file contents>
GO

[repeat section blocks for tiers 2-5; omit entire section block including header if no files in that tier]

-- --------------------------------------------------------
-- UNKNOWN (verify ordering manually)
-- --------------------------------------------------------
-- WARNING: unrecognized path -- verify ordering manually
-- File: <path>
<tier-99 file contents>
GO

7. Return: "SQL script written: Deployments/${deployDate}/deploy.sql with <N> objects"`,
    { phase: 'Build', label: 'sql-builder' }
  ),

  () => agent(
    `You are the README Builder agent.

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Target server: ${coordination.server}
Target database: ${coordination.database}
Flag: ${flag}
Baseline: ${coordination.baseline}
Commit messages since baseline: ${JSON.stringify(coordination.commitMessages)}

All projects (full SQL install):
${JSON.stringify(deployProjects, null, 2)}

Steps:
1. Overview paragraph (2-3 sentences): full SQL install for listed projects. Note tier-1 table backup if any tier-1 in sqlFiles.

2. ## Changes Since Baseline
   For EACH project in deployProjects:
   - If changedFiles empty: "No file changes since \`${coordination.baseline}\`."
   - Else list changedSql, changedCs (with git log -1 --pretty=%s per file), changedOther as bullet lists under ### ProjectName

3. ## SQL Files Deployed (full install)
   For EACH project in deployProjects, table:
   | # | File | Tier | Type |
   Every file in sqlFiles inventory (not diff-filtered).

4. ## Combined deploy.sql Objects
   | # | Object | Type | Source project | Notes |
   Same order as deploy.sql header.

5. Deploy steps based on flag:
   --saas:
     ## Step 1 -- Run batch package
     Unzip deploy-batch.zip; run Deploy-SQL.ps1 on batch server.
     ## Step 2 -- Run web package
     Unzip deploy-web.zip; run Deploy-Web.ps1 on web server -> ${coordination.webTarget || 'U:\\OpenAccess\\Customization\\'}
   --local:
     ## Step 1 -- Deploy via portal

6. For each project where csFiles.length > 0, add ## Step N -- Build and Deploy: <ProjectName>

7. Write ${repoRoot}/Deployments/${deployDate}/README.md
8. Return: "README written: Deployments/${deployDate}/README.md"`,
    { phase: 'Build', label: 'readme-builder' }
  ),
])

log('SQL script and README built')

// --- Phase 3: Commit ---

phase('Commit')

await agent(
  `You are the Commit agent.

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Environment: ${coordination.environment}

Steps (run all git commands from ${repoRoot}):
1. Stage and commit the deployment folder:
   git add Deployments/${deployDate}/
   git commit -m "Add ${deployDate} deployment package"

2. Create the environment-prefixed tag:
   git tag deploy/${coordination.environment}/${deployDate}

3. Read ${repoRoot}/deploy-state.json.
   If the file does not exist, start with {}.
   Parse the JSON. Upsert the entry for "${coordination.environment}":
   {
     "${coordination.environment}": {
       "tag": "deploy/${coordination.environment}/${deployDate}",
       "date": "${deployDate}"
     }
   }
   Preserve ALL other environment keys already in the file.
   Write the updated JSON back to ${repoRoot}/deploy-state.json.

4. Stage and commit deploy-state.json:
   git add deploy-state.json
   git commit -m "chore: update deploy-state for ${coordination.environment} ${deployDate}"

5. Return "Committed and tagged deploy/${coordination.environment}/${deployDate}"`,
  { phase: 'Commit', label: 'commit' }
)

log(`Committed and tagged deploy/${coordination.environment}/${deployDate}`)

// --- Phase 4: Guides (parallel) ---

phase('Guides')

const KRAKEN_ROOT = 'C:\\Users\\bseay\\source\\repos\\SkillsOfTheKraken'
const TEMPLATE_PATH = `${KRAKEN_ROOT}\\skills\\create-saas-deployment-package\\templates\\deployment-guide-template.md`
const repoRootPs1 = repoRoot.replace(/\\/g, '\\\\')

const componentGuideAgents = deployProjects.map(proj => () =>
  agent(
    `You are the Guide agent for project "${proj.projectName}".

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Baseline: ${coordination.baseline}
Template path: ${TEMPLATE_PATH}

Project data:
${JSON.stringify(proj, null, 2)}

Target server: ${coordination.server}
Target database: ${coordination.database}

Steps:
1. Read the template file at: ${TEMPLATE_PATH}
   If the file does not exist, return: "Template not found -- guide skipped for ${proj.projectName}"
   and stop.

2. Replace every {{token}} in the template:

   {{component_name}} -> "${proj.projectName}"

   {{date}} -> "${deployDate}"

   {{brief_description}}
   -> Run from ${repoRoot}: git log ${coordination.baseline}..HEAD --pretty="%s" -- ${proj.projectRoot} | head -1
      Format as: "${proj.projectName}: <commit subject>"
      If no commits found, use: "${proj.projectName}: deployment update ${deployDate}"

   {{implementation_steps}}
   -> Build numbered list:
      If sqlFiles.length > 0:
        "1. Run deploy.sql in SSMS against **${coordination.database}** on **${coordination.server}**. Safe to re-run (CREATE OR ALTER)."
      If csFiles.length > 0, append the next number:
        "N. Copy the following to the target JDA environment:
           - <dll name 1>
           - <dll name 2>
          Check ${proj.projectRoot}bin/Release/ for the actual DLL filenames.
          If that folder does not exist yet (not built), list: ${proj.projectName}.dll"

   {{code_drop}}
   -> Build from sqlFiles and csFiles:
      SQL (in deploy.sql):
        Tables: [tier-1 object names]
        Functions: [tier-3 object names]
        Views: [tier-4 object names]
        Stored Procedures: [tier-5 object names]
      DLLs (from ${proj.projectRoot}bin/Release/):
        [list .dll and .dll.config files found there, or "${proj.projectName}.dll" if folder absent]
      Omit SQL block if no sqlFiles. Omit DLLs block if no csFiles. Omit empty tier sub-sections.

   {{rollback_steps}}
   -> Generate per object type present:
      - If any tier-1 (Tables): "Back up <table_name> before running."
      - If tier 3/4/5 (Functions/Views/Procs): "SQL uses CREATE OR ALTER -- no rollback needed."
      - If csFiles: "Restore previous ${proj.projectName}.dll from backup in the target JDA environment."

   {{business_justification}} -> "" (leave blank)

3. Write the populated guide to:
   ${repoRoot}/Deployments/${deployDate}/${proj.projectName.replace(/ /g, '-')}.md

4. Return "Guide written: ${proj.projectName}.md"`,
    { phase: 'Guides', label: `guide:${proj.projectName}` }
  )
)

const excelGuideAgent = () => agent(
  `You are the Excel Guide agent.

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Baseline: ${coordination.baseline}
Server: ${coordination.server}
Database: ${coordination.database}

Changed projects (baseline diff):
${JSON.stringify(changedProjects, null, 2)}

All deploy projects (full SQL install):
${JSON.stringify(deployProjects, null, 2)}

Steps:
1. For each project in deployProjects, compute values for its Excel row:
   - BriefDescription: run from ${repoRoot}: git log ${coordination.baseline}..HEAD --pretty="%s" -- <projectRoot> | head -1
     Format: "<projectName>: <commit subject>"
   - ImplementSteps: SQL step if sqlFiles present; DLL step if csFiles present (same logic as guide agents)
   - RollbackSteps: Tables -> backup note; procs/views/functions -> "CREATE OR ALTER, no rollback"; DLLs -> restore note
   - CodeDrop: SQL objects by tier + DLL filenames

2. Run the following PowerShell script, substituting the real computed values into $rows
   (one hashtable per changed project):

$date = '${deployDate}'
$outputPath = '${repoRootPs1}\\Deployments\\${deployDate}\\Deployment Guide.xlsx'

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$wb = $excel.Workbooks.Add()
$ws = $wb.ActiveSheet
$ws.Name = "Deployment Guide"

$headers = @(
    "Brief Description","Implementation Steps","Rollback Steps",
    "Verification Steps","Code Drop","Test Results",
    "Customer Approval","Preferred Timeslot","Business Justification"
)
for ($i = 0; $i -lt $headers.Count; $i++) {
    $cell = $ws.Cells(1, $i + 1)
    $cell.Value2 = $headers[$i]
    $cell.Font.Bold = $true
}

$rows = @(
    @{
        BriefDescription = "<computed BriefDescription for project 1>"
        ImplementSteps   = "<computed ImplementSteps>"
        RollbackSteps    = "<computed RollbackSteps>"
        VerifySteps      = ""
        CodeDrop         = "<computed CodeDrop>"
        TestResults      = "Pending UAT"
        CustApproval     = "Pending"
        Timeslot         = ""
        BizJustification = ""
    }
)

$r = 2
foreach ($row in $rows) {
    $ws.Cells($r, 1).Value2 = $row.BriefDescription
    $ws.Cells($r, 2).Value2 = $row.ImplementSteps
    $ws.Cells($r, 3).Value2 = $row.RollbackSteps
    $ws.Cells($r, 4).Value2 = $row.VerifySteps
    $ws.Cells($r, 5).Value2 = $row.CodeDrop
    $ws.Cells($r, 6).Value2 = $row.TestResults
    $ws.Cells($r, 7).Value2 = $row.CustApproval
    $ws.Cells($r, 8).Value2 = $row.Timeslot
    $ws.Cells($r, 9).Value2 = $row.BizJustification
    $r++
}

$ws.Columns.AutoFit() | Out-Null
$wb.SaveAs("$outputPath")
$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
Write-Output "Excel saved: $outputPath"

3. If the script fails with a COM error (Excel not installed), report:
   "Excel generation failed: <error>. Markdown guides were generated successfully."
   Do not fail the workflow.

4. Return "Excel guide written: Deployment Guide.xlsx" or the warning.`,
  { phase: 'Guides', label: 'excel-guide' }
)

await parallel([...componentGuideAgents, excelGuideAgent])

log('All deployment guides generated')

// --- Phase 5: Package + Push ---

phase('Package')

const webTarget = coordination.webTarget || 'U:\\\\OpenAccess\\\\Customization\\\\'
const batchTarget = coordination.batchTarget || 'F:\\\\batch\\\\exe'

const saasSteps = `--saas steps:
Create TWO deployment ZIPs: deploy-web.zip (web artifacts) and deploy-batch.zip (SQL + guides).
All paths use Windows backslashes. Run all PowerShell from ${repoRoot}.

=== STEP 1: Stage web files ===

Create these folders:
  ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-web\\\\WebFiles\\\\bin
  ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-web\\\\WebFiles\\\\Custom
  ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-web\\\\WebFiles\\\\Custom\\\\Config
  ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-web\\\\WebFiles\\\\Custom\\\\Styles
  ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-web\\\\WebFiles\\\\Custom\\\\scripts
  ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-web\\\\WebFiles\\\\Images

For each project in coordination.projects, stage web artifacts from {projectRoot}bin/, bin/Release/, Views/, CSS/, Javascript/, Images/, Config/ as available.
Also stage for any project with csFiles if bin/Release missing — use bin/ or note in README.

If bin\\Release\\ doesn't exist, try bin\\ or note in README but continue.

Copy README.md from ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\ to stage-web\\\\.

Write ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-web\\\\Deploy-Web.ps1 with this exact content (plain ASCII only):

# Deploy-Web.ps1 - ${coordination.environment} deployment ${deployDate}
# Run on the WEB SERVER as Administrator.

param(
    [string]$WebTarget = "${webTarget}"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$webFiles  = Join-Path $scriptDir "WebFiles"

if (-not (Test-Path $webFiles)) {
    Write-Host "ERROR: WebFiles\\ not found next to Deploy-Web.ps1"
    exit 1
}

Write-Host "--- Web deployment ${deployDate} starting -> $WebTarget ---"

$dirs = @("Custom", "Custom\\Config", "Custom\\Styles", "Custom\\scripts", "bin", "Images")
foreach ($d in $dirs) {
    $t = Join-Path $WebTarget $d
    if (-not (Test-Path $t)) { New-Item -ItemType Directory -Force $t | Out-Null }
}

Copy-Item "$webFiles\\Custom\\*.ascx"     (Join-Path $WebTarget "Custom")         -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Custom\\Config\\*"  (Join-Path $WebTarget "Custom\\Config")  -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Custom\\Styles\\*"  (Join-Path $WebTarget "Custom\\Styles")  -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Custom\\scripts\\*" (Join-Path $WebTarget "Custom\\scripts") -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\bin\\*"             (Join-Path $WebTarget "bin")             -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Images\\*"          (Join-Path $WebTarget "Images")          -Force -ErrorAction SilentlyContinue

Write-Host "--- Web deployment ${deployDate} complete ---"


=== STEP 2: Stage SQL + guides (batch) ===

Create folder: ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-batch\\\\SQL

For each SQL file across all deployProjects (sorted by tier asc, then path asc), copy it to:
  stage-batch\\\\SQL\\\\{NN}_{original_filename}
where NN is a zero-padded two-digit sequence (01, 02, ...).
Read the source file from ${repoRootPs1}\\\\{path}.

Copy all *.md guide files (component guides like Automator.md, CXDerivedControls.md, Deployment Guide notes, etc.)
from ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\ to stage-batch\\\\.
Copy README.md from ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\ to stage-batch\\\\.

Write ${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-batch\\\\Deploy-SQL.ps1 with this exact content (plain ASCII only):

# Deploy-SQL.ps1 - ${coordination.environment} deployment ${deployDate}
# Run on the BATCH SERVER as Administrator.
# Prereq: F:\\batch\\bin\\set_env.ps1 must exist (standard batch infrastructure).

param(
    [string]$LogDir = "F:\\batch\\log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "--- SQL deployment ${deployDate} starting ---"

. "F:\\batch\\bin\\set_env.ps1"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlDir    = Join-Path $scriptDir "SQL"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force $LogDir | Out-Null }

$files = Get-ChildItem "$sqlDir\\*.sql" | Sort-Object Name
$total = $files.Count
$i     = 0

foreach ($file in $files) {
    $i++
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    Write-Host "[$i/$total] Running: $($file.Name)"

    & "F:\\batch\\bin\\cx_call_sql.ps1" \`
        -scriptName $scriptName \`
        -sqlScript  $file.FullName \`
        -logDir     $LogDir \`
        -dbServer   $env:DBSOURCECKB \`
        -dbName     $env:DBNAMECKB \`
        -dbUser     $env:DBUSER \`
        -dbPwd      $env:DBPWD

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$i/$total] FAILED: $($file.Name) (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }

    Write-Host "[$i/$total] OK: $($file.Name)"
}

Write-Host "--- SQL deployment ${deployDate} complete ($total files) ---"


=== STEP 3: Create ZIPs ===

Run this PowerShell (from ${repoRoot}):

$webStage   = '${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-web'
$batchStage = '${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\stage-batch'
$webZip     = '${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\deploy-web.zip'
$batchZip   = '${repoRootPs1}\\\\Deployments\\\\${deployDate}\\\\deploy-batch.zip'

Remove-Item $webZip   -ErrorAction SilentlyContinue
Remove-Item $batchZip -ErrorAction SilentlyContinue
Compress-Archive -Path "$webStage\\*"   -DestinationPath $webZip   -Force
Compress-Archive -Path "$batchStage\\*" -DestinationPath $batchZip -Force


=== STEP 4: Commit and push ===

From ${repoRoot}:
  git add "Deployments/${deployDate}/"
  git commit -m "Add deployment guides and package for ${deployDate}"
  git push
  git push origin deploy/${coordination.environment}/${deployDate}

Report: "Package done. deploy-web.zip and deploy-batch.zip created in Deployments/${deployDate}/"
`

const localSteps = `--local steps:
1. Stage and commit the guides (from ${repoRoot}):
   git add "Deployments/${deployDate}/"
   git commit -m "Add deployment guides for ${deployDate}"

2. Push commits and tag:
   git push
   git push origin deploy/${coordination.environment}/${deployDate}

3. Report: "Package ready. Committed as deploy/${coordination.environment}/${deployDate}. Use portal deploy button per project for local execution."`

await agent(
  `You are the Package + Push agent.

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Environment: ${coordination.environment}
Flag: ${flag}

${flag === '--saas' ? saasSteps : localSteps}`,
  { phase: 'Package', label: 'package-push' }
)

return {
  status: 'complete',
  tag: `deploy/${coordination.environment}/${deployDate}`,
  date: deployDate,
  flag,
}
