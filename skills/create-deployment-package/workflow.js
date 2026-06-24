export const meta = {
  name: 'create-deployment-package',
  description: 'Multi-agent deployment package builder: gather changes, build SQL + README, guides, ZIP',
  phases: [
    { title: 'Coordinate', detail: 'Resolve baseline, env, server/db from _package-request.json and env-config.json' },
    { title: 'Gather', detail: 'One agent per project: git diff, classify SQL tiers + C# files' },
    { title: 'Build', detail: 'SQL Builder + README Builder in parallel' },
    { title: 'Commit', detail: 'git commit + tag + deploy-state.json' },
    { title: 'Guides', detail: 'One guide agent per changed component + Excel agent in parallel' },
    { title: 'Package', detail: 'Generate Deploy.ps1 + ZIP (--saas) or push only (--local)' },
  ],
}

const { flag, repoRoot } = args

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
  },
}

const PROJECT_GATHER_SCHEMA = {
  type: 'object',
  required: ['projectName', 'projectRoot', 'sqlFiles', 'csFiles', 'hasChanges'],
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
   Extract: projects (string array), environment (string), baseline (string or null), deployType (string).
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
6. Return structured output with all required fields.`,
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
1. From ${repoRoot}, run:
   git diff --name-only ${coordination.baseline} HEAD -- ${projectName}/
2. Partition results:

   SQL files: any .sql file. Assign tier by these rules (filename-based takes priority):
   - Tier 1 (Tables): path contains "Tables/" AND filename does NOT start with "Populate"
   - Tier 2 (Data): filename starts with "Populate" or "ckbcustom.Populate"
   - Tier 3 (Functions): path contains "Functions/"
   - Tier 4 (Views): path contains "Views/"
   - Tier 5 (Stored Procedures): path contains "Stored Procedures/" OR "Store Procedures/" OR "Procedures/"
   - Tier 99 (Unknown): anything not matching tiers 1-5

   C# files: any .cs file.

   Ignore entirely: .md, .csproj, .sqlproj, .sln, .json, .ps1, .html,
   and anything under Deployments/, docs/, .claude/

3. Set hasChanges=true if any SQL or C# files found, false if both arrays are empty.
4. Return structured output.`,
      { phase: 'Gather', schema: PROJECT_GATHER_SCHEMA, label: `gather:${projectName}` }
    )
  )
)

const gathered = gatherResults.filter(Boolean)
const changedProjects = gathered.filter(g => g.hasChanges)

log(`${changedProjects.length}/${coordination.projects.length} projects have changes`)

if (changedProjects.length === 0) {
  log('No deployable changes found since ' + coordination.baseline + '. Stopping.')
  return { status: 'no-changes', baseline: coordination.baseline }
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

Changed projects with SQL files:
${JSON.stringify(changedProjects.map(p => ({ name: p.projectName, sqlFiles: p.sqlFiles })), null, 2)}

Steps:
1. Collect ALL sqlFiles across all changed projects into one list.
   Sort: by tier ascending (1 then 2 then 3 then 4 then 5 then 99), then alphabetically by path within each tier.
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
Commit messages since baseline: ${JSON.stringify(coordination.commitMessages)}

Changed projects:
${JSON.stringify(changedProjects, null, 2)}

Steps:
1. Write an overview paragraph (2-3 sentences) summarizing what this deployment covers,
   based on the commit messages and changed project/file names.
   If any table changed (tier-1 SQL file), add: "The <table_name> table is modified -- verify existing rows are preserved if needed."

2. Build the Step 1 block based on flag:
   If flag is --saas:
     ## Step 1 -- Run deployment package
     Unzip deploy-package.zip on the batch server. Run Deploy.ps1 as Administrator.
     The script fetches credentials from Azure Key Vault and runs deploy.sql against
     **${coordination.database}** on **${coordination.server}**. Safe to re-run.

   If flag is --local:
     ## Step 1 -- Deploy via portal
     Use the portal deploy button for each changed project. The watcher handles local execution.
     SQL is in deploy.sql if manual SSMS execution is needed.

3. Add the SQL object table after Step 1:
   | # | Object | Type | Notes |
   (derive from sqlFiles across all changedProjects, same order as deploy.sql)

4. For each project where csFiles.length > 0, add a numbered step:
   ## Step N -- Build and Deploy: <ProjectName>
   **Changes:**
   - <cs file path> -- <run: git log -1 --pretty=%s -- <file> from ${repoRoot}>
   **Steps:** Build Release in Visual Studio, copy DLLs from bin/Release/ to target.

5. Create the directory ${repoRoot}/Deployments/${deployDate}/ if it does not exist.
6. Write to ${repoRoot}/Deployments/${deployDate}/README.md
7. Return: "README written: Deployments/${deployDate}/README.md"`,
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
const TEMPLATE_PATH = `${KRAKEN_ROOT}\\skills\\create-deployment-package\\templates\\deployment-guide-template.md`

const componentGuideAgents = changedProjects.map(proj => () =>
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

Changed projects:
${JSON.stringify(changedProjects, null, 2)}

Steps:
1. For each changed project, compute values for its Excel row:
   - BriefDescription: run from ${repoRoot}: git log ${coordination.baseline}..HEAD --pretty="%s" -- <projectRoot> | head -1
     Format: "<projectName>: <commit subject>"
   - ImplementSteps: SQL step if sqlFiles present; DLL step if csFiles present (same logic as guide agents)
   - RollbackSteps: Tables -> backup note; procs/views/functions -> "CREATE OR ALTER, no rollback"; DLLs -> restore note
   - CodeDrop: SQL objects by tier + DLL filenames

2. Run the following PowerShell script, substituting the real computed values into $rows
   (one hashtable per changed project):

$date = '${deployDate}'
$outputPath = '${repoRoot.replace(/\\/g, '\\\\')}\\Deployments\\${deployDate}\\Deployment Guide.xlsx'

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

const saasSteps = `--saas steps:
1. Generate the Deploy.ps1 file at:
   ${repoRoot}\\Deployments\\${deployDate}\\Deploy.ps1

   Write this exact content (plain ASCII only -- no Unicode or box-drawing characters):

# Deploy.ps1 - ${coordination.environment} deployment ${deployDate}
# Run as Administrator on the batch server.
# Prereq: F:\\batch\\bin\\set_env.ps1 must exist (standard batch infrastructure).

param(
    [string]$WebTarget   = "U:\\OpenAccess\\Customization\\",
    [string]$BatchTarget = "F:\\batch\\exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "--- Starting deployment ${deployDate} ---"

# Load environment and fetch DB credentials from Azure Key Vault
. "F:\\batch\\bin\\set_env.ps1"

# Run SQL deployment
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlScript  = Join-Path $scriptDir "deploy.sql"

& "F:\\batch\\bin\\cx_call_sql.ps1" \`
    -scriptName "deploy-${deployDate}" \`
    -sqlScript  $sqlScript \`
    -logDir     "F:\\batch\\log" \`
    -dbServer   $env:DBSOURCECKB \`
    -dbName     $env:DBNAMECKB \`
    -dbUser     $env:DBUSER \`
    -dbPwd      $env:DBPWD

if ($LASTEXITCODE -ne 0) {
    Write-Host "SQL deployment FAILED. Exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "--- SQL deployment complete ---"
Write-Host "--- Deployment ${deployDate} finished successfully ---"

2. Create the ZIP archive using PowerShell (run from ${repoRoot}):
   $src = "${repoRoot}\\Deployments\\${deployDate}"
   $tmp = "${repoRoot}\\Deployments\\deploy-package-tmp.zip"
   $dest = "${repoRoot}\\Deployments\\${deployDate}\\deploy-package.zip"
   Compress-Archive -Path "$src\\*" -DestinationPath $tmp -Force
   Remove-Item $dest -ErrorAction SilentlyContinue
   Move-Item $tmp $dest

3. Stage and commit guides + Deploy.ps1 + ZIP (from ${repoRoot}):
   git add "Deployments/${deployDate}/"
   git commit -m "Add deployment guides and package for ${deployDate}"

4. Push commits and tag:
   git push
   git push origin deploy/${coordination.environment}/${deployDate}

5. Check if C:\\Users\\bseay\\source\\repos\\SkillsOfTheKraken exists.
   If yes, check git status of:
   skills/create-deployment-package/templates/deployment-guide-template.md
   If modified or untracked, commit and push it:
     git add skills/create-deployment-package/templates/deployment-guide-template.md
     git commit -m "Add deployment guide markdown template"
     git push

6. Report: "Deployment package created and tagged as deploy/${coordination.environment}/${deployDate}. ZIP at Deployments/${deployDate}/deploy-package.zip"`

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
