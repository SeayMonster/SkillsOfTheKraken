export const meta = {
  name: 'create-saas-deployment-package',
  description: 'Multi-agent deployment package builder: gather changes, build SQL + README, guides, ZIP',
  phases: [
    { title: 'Coordinate', detail: 'Resolve baseline, env, server/db from _package-request.json and env-config.json' },
    { title: 'Gather', detail: 'One agent per project: git diff, classify SQL tiers + C# files' },
    { title: 'Compile', detail: 'msbuild Release + collect web artifacts (DLL, ASCX, CSS, JS, config, images) into WebFiles/' },
    { title: 'Build', detail: 'SQL Builder + README Builder in parallel' },
    { title: 'Commit', detail: 'git commit + tag + deploy-state.json' },
    { title: 'Guides', detail: 'One guide agent per changed component + Excel agent in parallel' },
    { title: 'Package', detail: 'Generate Deploy.ps1 (SQL + web copy) + ZIP via staging folder (--saas) or push only (--local)' },
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
  required: ['projectName', 'projectRoot', 'sqlFiles', 'csFiles', 'changedFiles', 'hasChanges'],
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
    changedFiles: {
      type: 'array',
      description: 'Files changed since baseline (git diff). Used for README change summary.',
      items: { type: 'string' },
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
0. Find the actual project root folder for "${projectName}":
   Run from ${repoRoot}:
   (Get-ChildItem "${repoRoot}" -Recurse -Filter "${projectName}.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DirectoryName)

   Compute the relative path from ${repoRoot} to that folder.
   Example: if full path is "C:\\...\\Academy\\OA_LifecycleManagement", relative path is "OA_LifecycleManagement".
   If .csproj not found, fall back to "${projectName}" as the relative path.
   Store this relative path as $projectFolder. Set projectRoot in your output to this relative path.

1. From ${repoRoot}, run both commands:
   a. git ls-files -- $projectFolder/
      This returns ALL tracked files — treat every deployment as a fresh install.
   b. git diff --name-only ${coordination.baseline} HEAD -- $projectFolder/
      This returns files changed since baseline — used for the README change summary.

2. Partition the git ls-files results (step 1a):

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

3. changedFiles: the raw list from step 1b (git diff), filtered to exclude .md/.json/.ps1/.html.
4. Set hasChanges=true always (all files included for fresh-install completeness).
5. Set projectRoot to the relative path resolved in step 0 (e.g. "OA_LifecycleManagement", NOT the full absolute path).
6. Return structured output.`,
      { phase: 'Gather', schema: PROJECT_GATHER_SCHEMA, label: `gather:${projectName}` }
    )
  )
)

const gathered = gatherResults.filter(Boolean)

log(`Gathered ${gathered.length}/${coordination.projects.length} projects for fresh-install package`)

const deployDate = coordination.date

// --- Phase 1c: Compile + Collect Web Artifacts ---

phase('Compile')

// Clear stale WebFiles from any previous partial run before compiling
await agent(
  `Clear stale WebFiles directory before fresh compile.

Run this PowerShell:
$wf = "${repoRoot}\\Deployments\\${deployDate}\\WebFiles"
if (Test-Path $wf) { Remove-Item $wf -Recurse -Force; Write-Host "Cleared stale WebFiles" } else { Write-Host "No stale WebFiles to clear" }

Return: "WebFiles cleared"`,
  { phase: 'Compile', label: 'clear-webfiles' }
)

// Always compile all selected projects — package must be complete for new installs
const projectsWithCs = gathered.filter(p => p.csFiles && p.csFiles.length > 0)

if (projectsWithCs.length > 0) {
  await parallel(
    projectsWithCs.map(proj => () =>
      agent(
        `You are the Compile + Collect agent for project "${proj.projectName}".

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Project root: ${proj.projectRoot}

Steps:
1. Find msbuild.exe by running this PowerShell:
   Get-ChildItem "C:\\Program Files\\Microsoft Visual Studio" -Recurse -Filter "msbuild.exe" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*\\Current\\Bin\\*" } | Select-Object -First 1 -ExpandProperty FullName
   If blank, retry without the Where-Object filter and take the first result.

2. Find the .csproj in ${proj.projectRoot}:
   Get-ChildItem "${proj.projectRoot}" -Filter "*.csproj" | Select-Object -First 1 -ExpandProperty FullName

3. Build Release:
   $msbuildOut = & "<msbuild>" "<csproj>" /p:Configuration=Release /p:PostBuildEvent="" /v:minimal /nologo 2>&1
   Write-Host $msbuildOut
   The build may exit non-zero if a post-build bat (CopyWebUI.bat) fails — pass /p:PostBuildEvent="" to skip it.
   Confirm success by checking for the "-> <path>\\bin\\*.dll" line in msbuild output.
   If the DLL line is missing and the exit code is non-zero, report the error and stop.
   Parse the built DLL path from that line: $builtDll = ($msbuildOut | Select-String "->\\s+(.+\\.dll)").Matches[0].Groups[1].Value.Trim()

4. Create WebFiles directory structure at ${repoRoot}\\Deployments\\${deployDate}\\WebFiles\\ :
   New-Item -ItemType Directory -Force on each of:
     WebFiles\\Custom
     WebFiles\\Custom\\Config
     WebFiles\\Custom\\Styles
     WebFiles\\Custom\\scripts
     WebFiles\\bin
     WebFiles\\Images

5. Copy artifacts (skip silently if source path does not exist):
   a. ASCX views:    ${proj.projectRoot}\\Views\\*.ascx           → WebFiles\\Custom\\
   b. Project DLL:   Copy $builtDll (parsed from msbuild output in step 3) → WebFiles\\bin\\
      IMPORTANT: Only copy the single DLL identified by msbuild ($builtDll). Do NOT glob-copy all Cantactix.* or CX.* DLLs — those may belong to other projects and pollute this package.
   c. CSS:           ${proj.projectRoot}\\CSS\\*.css               → WebFiles\\Custom\\Styles\\
   d. JavaScript:    ${proj.projectRoot}\\Javascript\\*.js         → WebFiles\\Custom\\scripts\\
   e. Config:        ${repoRoot}\\Config\\CrispCustomizations.config → WebFiles\\Custom\\Config\\
   f. Images:        ${proj.projectRoot}\\Images\\dbstatus_*.png   → WebFiles\\Images\\
                     ${proj.projectRoot}\\Images\\dbstatus_*.svg   → WebFiles\\Images\\
   g. Third-party DLLs — copy from ${proj.projectRoot}\\bin\\ any file matching:
        Serilog.dll, Serilog.Sinks.*.dll, Dapper.dll
      to WebFiles\\bin\\

6. Return: "Compiled and collected: ${proj.projectName} — <N> files in WebFiles/"`,
        { phase: 'Compile', label: `compile:${proj.projectName}` }
      )
    )
  )
  log(`Compiled ${projectsWithCs.length} project(s) and collected web artifacts`)
} else {
  log('No C# projects in selection — skipping compile')
}

const hasWebArtifacts = projectsWithCs.length > 0  // based on all gathered projects, not just changed

// --- Phase 2: Build (SQL Builder + README Builder in parallel) ---

phase('Build')

await parallel([
  () => agent(
    `You are the SQL Builder agent. Copy SQL files into the deployment SQL/ folder with numeric prefixes for execution order.

Repo root: ${repoRoot}
Deploy date: ${deployDate}

SQL files (sorted by tier, then alpha — drop scripts last within their tier):
${JSON.stringify(
  gathered.flatMap(p => p.sqlFiles)
    .sort((a, b) => {
      if (a.tier !== b.tier) return a.tier - b.tier
      const aIsDrop = a.path.toLowerCase().includes('drop')
      const bIsDrop = b.path.toLowerCase().includes('drop')
      if (aIsDrop !== bIsDrop) return aIsDrop ? 1 : -1
      return a.path.localeCompare(b.path)
    }),
  null, 2
)}

Steps:
1. Create ${repoRoot}\\Deployments\\${deployDate}\\SQL\\ (New-Item -ItemType Directory -Force).

2. For each SQL file in the sorted order above, assign a zero-padded numeric prefix (01_, 02_, etc.)
   and copy it to ${repoRoot}\\Deployments\\${deployDate}\\SQL\\<NN>_<filename>.
   Example: "cx_pog_copy_ins.sql" becomes "01_cx_pog_copy_ins.sql".
   Use Copy-Item.

3. For each copied file, clean it for ExecuteNonQuery compatibility:

   $grants = @()
   foreach ($sqlFile in Get-ChildItem "${repoRoot}\\Deployments\\${deployDate}\\SQL\\*.sql") {
       $content = Get-Content $sqlFile.FullName -Raw -Encoding UTF8
       # Strip BOM if present
       if ($content.StartsWith([char]0xFEFF)) { $content = $content.Substring(1) }
       # Strip SET ANSI_NULLS / SET QUOTED_IDENTIFIER lines (preamble not needed with ExecuteNonQuery)
       $content = [regex]::Replace($content, '(?im)^\s*SET\s+(ANSI_NULLS|QUOTED_IDENTIFIER)\s+(ON|OFF)\s*$', '')
       # Extract all GRANT ... TO ... blocks (may span multiple lines) before stripping GO
       $grantMatches = [regex]::Matches($content, '(?is)GRANT\b.*?TO\s+\w+\s*;?')
       foreach ($m in $grantMatches) {
           $clean = ($m.Value -replace '\s+', ' ').Trim().TrimEnd(';') + ';'
           if ($grants -notcontains $clean) { $grants += $clean }
       }
       # Remove GRANT blocks and all GO batch separators
       $content = [regex]::Replace($content, '(?is)GRANT\b.*?TO\s+\w+\s*;?', '')
       $content = $content -replace '(?m)^GO\s*$', ''
       Set-Content $sqlFile.FullName $content.TrimEnd() -Encoding UTF8
   }

   # Write consolidated grants file (runs last — objects must exist first)
   if ($grants.Count -gt 0) {
       $grantsPath = "${repoRoot}\\Deployments\\${deployDate}\\SQL\\99_grants.sql"
       ($grants | Sort-Object -Unique) -join "\`n" | Set-Content $grantsPath -Encoding UTF8
       Write-Host "99_grants.sql written with $($grants.Count) GRANT statement(s)"
   }

4. Return: "SQL files copied: <N> files with numeric prefixes. GRANT statements consolidated into 99_grants.sql."`,
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
${JSON.stringify(gathered, null, 2)}

Steps:
1. Write an overview paragraph (2-3 sentences) summarizing what this deployment covers,
   based on the commit messages and changed project/file names.
   If any table changed (tier-1 SQL file), add: "The <table_name> table is modified -- verify existing rows are preserved if needed."

2. Build the Step 1 block based on flag. IMPORTANT: Always use the exact flag value below -- never substitute --local text when flag is --saas, even if there are no SQL files.
   If flag is --saas:
     ## Step 1 -- Run SQL deployment (batch server)
     Extract deploy-batch.zip on the batch server. Run Deploy-SQL.ps1 as Administrator.
     The script calls cx_call_sql.ps1 per file in SQL/ (sorted by numeric prefix) against
     **${coordination.database}** on **${coordination.server}**. Safe to re-run (all CREATE OR ALTER).
     (If no SQL files in this deployment, note that and omit the SQL object table.)

   If flag is --local:
     ## Step 1 -- Deploy via portal
     Use the portal deploy button for each changed project. The watcher handles local execution.
     For manual SQL execution: run files in SQL/ via SSMS in numeric-prefix order.

3. Add the SQL object table after Step 1:
   | # | File | Type | Notes |
   (derive from sqlFiles across all gathered, in numeric-prefix order)

4. For each project where csFiles.length > 0, add a numbered step:
   ## Step N -- Build and Deploy: <ProjectName>

   **What changed since last deploy:**
   (list each file from project.changedFiles, one per line with a dash. If changedFiles is empty, write "(no C# changes since last deploy — package includes all files for fresh install)")

   **All files in this package:**
   (list each file from project.csFiles, one per line with a dash)

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
const TEMPLATE_PATH = `${KRAKEN_ROOT}\\skills\\create-saas-deployment-package\\templates\\deployment-guide-template.md`

const componentGuideAgents = gathered.map(proj => () =>
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
        "1. Run Deploy-SQL.ps1 on the batch server (runs SQL/ files in numeric-prefix order via cx_call_sql). Safe to re-run (CREATE OR ALTER)."
      If csFiles.length > 0, append the next number:
        "N. Copy the following to the target JDA environment:
           - <dll name 1>
           - <dll name 2>
          Check ${proj.projectRoot}bin/Release/ for the actual DLL filenames.
          If that folder does not exist yet (not built), list: ${proj.projectName}.dll"

   {{code_drop}}
   -> Build from sqlFiles and csFiles:
      SQL (in SQL/ folder, numeric-prefix order):
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

const repoRootEscaped = repoRoot ? repoRoot.replace(/\\/g, '\\\\') : repoRoot

const excelGuideAgent = () => agent(
  `You are the Excel Guide agent.

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Baseline: ${coordination.baseline}
Server: ${coordination.server}
Database: ${coordination.database}

Changed projects:
${JSON.stringify(gathered, null, 2)}

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
$outputPath = '${repoRootEscaped}\\Deployments\\${deployDate}\\Deployment Guide.xlsx'

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

const hasSqlFiles = gathered.some(p => p.sqlFiles && p.sqlFiles.length > 0)

const sqlDeployStep = hasSqlFiles
  ? `1a. Generate Deploy-SQL.ps1 at:
    ${repoRoot}\\Deployments\\${deployDate}\\Deploy-SQL.ps1

    Write this exact content (plain ASCII only -- no Unicode or box-drawing characters):

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

Write-Host "--- SQL deployment ${deployDate} complete ($total files) ---"`
  : `1a. (No SQL files in this deployment -- skip step 1a, no Deploy-SQL.ps1 needed.)`

const webDeployStep = hasWebArtifacts
  ? `1b. Generate Deploy-Web.ps1 at:
    ${repoRoot}\\Deployments\\${deployDate}\\Deploy-Web.ps1

    Write this exact content (plain ASCII only -- no Unicode or box-drawing characters):

# Deploy-Web.ps1 - ${coordination.environment} deployment ${deployDate}
# Run on the WEB SERVER as Administrator.

param(
    [string]$WebTarget = "U:\\OpenAccess\\Customization\\"
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

$dirs = @("Custom","Custom\\Config","Custom\\Styles","Custom\\scripts","bin","Images")
foreach ($d in $dirs) {
    $t = Join-Path $WebTarget $d
    if (-not (Test-Path $t)) { New-Item -ItemType Directory -Force $t | Out-Null }
}

Copy-Item "$webFiles\\Custom\\*.ascx"      (Join-Path $WebTarget "Custom")          -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Custom\\Config\\*"   (Join-Path $WebTarget "Custom\\Config")  -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Custom\\Styles\\*"   (Join-Path $WebTarget "Custom\\Styles")  -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Custom\\scripts\\*"  (Join-Path $WebTarget "Custom\\scripts") -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\bin\\*"              (Join-Path $WebTarget "bin")             -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Images\\*"           (Join-Path $WebTarget "Images")          -Force -ErrorAction SilentlyContinue

Write-Host "--- Web deployment ${deployDate} complete ---"`
  : `1b. (No C# projects changed -- skip step 1b, no Deploy-Web.ps1 needed.)`

const batchZipBlock = hasSqlFiles
  ? `   # deploy-batch.zip: SQL\\ folder + Deploy-SQL.ps1 + docs
   if (Test-Path $batchStage) { Remove-Item $batchStage -Recurse -Force }
   New-Item -ItemType Directory -Force $batchStage | Out-Null
   Copy-Item "$deployDir\\SQL"              "$batchStage\\SQL" -Recurse
   Copy-Item "$deployDir\\Deploy-SQL.ps1"   "$batchStage\\"
   Copy-Item "$deployDir\\README.md"        "$batchStage\\"
   Get-ChildItem $deployDir -Filter "*.md" | Where-Object { $_.Name -ne "README.md" } | ForEach-Object { Copy-Item $_.FullName "$batchStage\\" }
   $batchItems = Get-ChildItem $batchStage | Select-Object -ExpandProperty FullName
   Compress-Archive -Path $batchItems -DestinationPath $batchDest
   Write-Host "deploy-batch.zip created: $batchDest"`
  : `   # No SQL files -- skipping deploy-batch.zip`

if (flag === '--saas') {

  // --- 5a: Write deploy scripts ---
  await agent(
    `You are the Write Scripts agent. Your ONLY job is to write two PowerShell scripts to disk. Nothing else.

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Environment: ${coordination.environment}

${hasSqlFiles ? `TASK 1: Write Deploy-SQL.ps1
Write the file at exactly: ${repoRoot}\\Deployments\\${deployDate}\\Deploy-SQL.ps1

Use Set-Content with -Encoding UTF8. Content (copy exactly, plain ASCII only):

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

After writing, confirm with: Test-Path "${repoRoot}\\Deployments\\${deployDate}\\Deploy-SQL.ps1"
If False, Write-Error "FAILED to write Deploy-SQL.ps1" and exit 1.` : '(No SQL files — skip Deploy-SQL.ps1)'}

${hasWebArtifacts ? `TASK 2: Write Deploy-Web.ps1
Write the file at exactly: ${repoRoot}\\Deployments\\${deployDate}\\Deploy-Web.ps1

Use Set-Content with -Encoding UTF8. Content (copy exactly, plain ASCII only):

# Deploy-Web.ps1 - ${coordination.environment} deployment ${deployDate}
# Run on the WEB SERVER as Administrator.

param(
    [string]$WebTarget = "U:\\OpenAccess\\Customization\\"
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

$dirs = @("Custom","Custom\\Config","Custom\\Styles","Custom\\scripts","bin","Images")
foreach ($d in $dirs) {
    $t = Join-Path $WebTarget $d
    if (-not (Test-Path $t)) { New-Item -ItemType Directory -Force $t | Out-Null }
}

Copy-Item "$webFiles\\Custom\\*.ascx"      (Join-Path $WebTarget "Custom")          -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Custom\\Config\\*"   (Join-Path $WebTarget "Custom\\Config")  -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Custom\\Styles\\*"   (Join-Path $WebTarget "Custom\\Styles")  -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Custom\\scripts\\*"  (Join-Path $WebTarget "Custom\\scripts") -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\bin\\*"              (Join-Path $WebTarget "bin")             -Force -ErrorAction SilentlyContinue
Copy-Item "$webFiles\\Images\\*"           (Join-Path $WebTarget "Images")          -Force -ErrorAction SilentlyContinue

Write-Host "--- Web deployment ${deployDate} complete ---"

After writing, confirm with: Test-Path "${repoRoot}\\Deployments\\${deployDate}\\Deploy-Web.ps1"
If False, Write-Error "FAILED to write Deploy-Web.ps1" and exit 1.` : '(No web artifacts — skip Deploy-Web.ps1)'}

Return: "Scripts written: [list of files written]"`,
    { phase: 'Package', label: 'write-scripts' }
  )

  // --- 5b: Create ZIPs ---
  await agent(
    `You are the Zip agent. Create two ZIP archives from the deployment folder.

Repo root: ${repoRoot}
Deploy date: ${deployDate}

Run this PowerShell exactly:

$deployDir   = "${repoRoot}\\Deployments\\${deployDate}"
$tmpBase     = [System.IO.Path]::GetTempPath()
$batchStage  = $tmpBase + "batch-stage-${deployDate}"
$webStage    = $tmpBase + "web-stage-${deployDate}"
$batchDest   = "$deployDir\\deploy-batch.zip"
$webDest     = "$deployDir\\deploy-web.zip"

${hasSqlFiles ? `# deploy-batch.zip
if (Test-Path $batchStage) { Remove-Item $batchStage -Recurse -Force }
if (Test-Path $batchDest)  { Remove-Item $batchDest -Force }
New-Item -ItemType Directory -Force $batchStage | Out-Null
if (-not (Test-Path "$deployDir\\Deploy-SQL.ps1")) { Write-Error "ABORT: Deploy-SQL.ps1 missing"; exit 1 }
if (-not (Test-Path "$deployDir\\SQL"))            { Write-Error "ABORT: SQL folder missing"; exit 1 }
Copy-Item "$deployDir\\SQL"            "$batchStage\\SQL" -Recurse
Copy-Item "$deployDir\\Deploy-SQL.ps1" "$batchStage\\"
Copy-Item "$deployDir\\README.md"      "$batchStage\\"
Get-ChildItem $deployDir -Filter "*.md" | Where-Object { $_.Name -ne "README.md" } | ForEach-Object { Copy-Item $_.FullName "$batchStage\\" }
$batchItems = Get-ChildItem $batchStage | Select-Object -ExpandProperty FullName
Compress-Archive -Path $batchItems -DestinationPath $batchDest
Write-Host "deploy-batch.zip created"` : '# No SQL files -- skipping deploy-batch.zip'}

${hasWebArtifacts ? `# deploy-web.zip
if (Test-Path $webStage) { Remove-Item $webStage -Recurse -Force }
if (Test-Path $webDest)  { Remove-Item $webDest -Force }
New-Item -ItemType Directory -Force $webStage | Out-Null
if (-not (Test-Path "$deployDir\\Deploy-Web.ps1")) { Write-Error "ABORT: Deploy-Web.ps1 missing"; exit 1 }
Copy-Item "$deployDir\\README.md"      "$webStage\\"
Copy-Item "$deployDir\\Deploy-Web.ps1" "$webStage\\"
Copy-Item "$deployDir\\WebFiles"       "$webStage\\WebFiles" -Recurse
$stagedDlls = Get-ChildItem "$webStage\\WebFiles\\bin" -Filter "*.dll" -ErrorAction SilentlyContinue
if (-not $stagedDlls) { Write-Error "ABORT: no DLLs in WebFiles\\bin"; exit 1 }
$webItems = Get-ChildItem $webStage | Select-Object -ExpandProperty FullName
Compress-Archive -Path $webItems -DestinationPath $webDest
Write-Host "deploy-web.zip created"` : '# No web artifacts -- skipping deploy-web.zip'}

Return: "Zips created: [list]"`,
    { phase: 'Package', label: 'create-zips' }
  )

  // --- 5c: Commit + Push ---
  await agent(
    `You are the Push agent. Commit and push the completed deployment package.

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Environment: ${coordination.environment}

Steps (run all git commands from ${repoRoot}):
1. git add "Deployments/${deployDate}/"
2. git commit -m "Add deployment guides and package for ${deployDate}"
3. git push
4. git push origin deploy/${coordination.environment}/${deployDate}
5. Return: "Pushed deploy/${coordination.environment}/${deployDate}"`,
    { phase: 'Package', label: 'push' }
  )

} else {
  // --local
  await agent(
    `You are the Push agent (local mode).

Repo root: ${repoRoot}
Deploy date: ${deployDate}
Environment: ${coordination.environment}

Steps (run all git commands from ${repoRoot}):
1. git add "Deployments/${deployDate}/"
2. git commit -m "Add deployment guides for ${deployDate}"
3. git push
4. git push origin deploy/${coordination.environment}/${deployDate}
5. Return: "Package ready. Committed as deploy/${coordination.environment}/${deployDate}."`,
    { phase: 'Package', label: 'push-local' }
  )
}

// --- Phase 6: Validate ---
phase('Validate')

await agent(
  `You are the Validate agent. Verify the deployment package at ${repoRoot}\\Deployments\\${deployDate}\\ is complete and correct.

Run these checks in PowerShell and report PASS or FAIL for each:

1. deploy-batch.zip exists:
   Test-Path "${repoRoot}\\Deployments\\${deployDate}\\deploy-batch.zip"

2. deploy-web.zip exists (--saas only — skip if flag is --local):
   Test-Path "${repoRoot}\\Deployments\\${deployDate}\\deploy-web.zip"

3. deploy-batch.zip contains at least one .sql file:
   $z = [System.IO.Compression.ZipFile]::OpenRead("${repoRoot}\\Deployments\\${deployDate}\\deploy-batch.zip")
   $hasSql = ($z.Entries | Where-Object { $_.Name -like "*.sql" }).Count -gt 0
   $z.Dispose()
   $hasSql

4. deploy-web.zip contains at least one custom DLL per selected C# project (--saas only, skip if no C# projects):
   Add-Type -AssemblyName System.IO.Compression.FileSystem
   $z = [System.IO.Compression.ZipFile]::OpenRead("${repoRoot}\\Deployments\\${deployDate}\\deploy-web.zip")
   $customDlls = @($z.Entries | Where-Object { ($_.FullName -like "*bin/*.dll" -or $_.FullName -like "*bin\\\\*.dll") -and ($_.Name -like "Cantactix.*" -or $_.Name -like "CX.*") })
   $z.Dispose()
   $expectedCount = ${projectsWithCs.length}
   Write-Host "Custom DLLs in zip: $($customDlls.Count) (expected >= $expectedCount)"
   Write-Host "Found: $($customDlls | Select-Object -ExpandProperty Name | Sort-Object)"
   if ($customDlls.Count -lt $expectedCount) {
       Write-Error "VALIDATION FAILED: deploy-web.zip has $($customDlls.Count) custom DLL(s) but $expectedCount project(s) selected. Missing DLL for at least one project."
       exit 1
   }

5. Deploy-Web.ps1 exists in deploy-web.zip (--saas only, skip if no C# projects):
   Add-Type -AssemblyName System.IO.Compression.FileSystem
   $z = [System.IO.Compression.ZipFile]::OpenRead("${repoRoot}\\Deployments\\${deployDate}\\deploy-web.zip")
   $hasDeployScript = ($z.Entries | Where-Object { $_.Name -eq "Deploy-Web.ps1" }).Count -gt 0
   $z.Dispose()
   if (-not $hasDeployScript) { Write-Error "VALIDATION FAILED: Deploy-Web.ps1 missing from deploy-web.zip"; exit 1 }
   Write-Host "PASS: Deploy-Web.ps1 found in deploy-web.zip"

6. Deploy-SQL.ps1 exists in deploy-batch.zip (skip if no SQL files):
   Add-Type -AssemblyName System.IO.Compression.FileSystem
   $z = [System.IO.Compression.ZipFile]::OpenRead("${repoRoot}\\Deployments\\${deployDate}\\deploy-batch.zip")
   $hasSqlScript = ($z.Entries | Where-Object { $_.Name -eq "Deploy-SQL.ps1" }).Count -gt 0
   $z.Dispose()
   if (-not $hasSqlScript) { Write-Error "VALIDATION FAILED: Deploy-SQL.ps1 missing from deploy-batch.zip"; exit 1 }
   Write-Host "PASS: Deploy-SQL.ps1 found in deploy-batch.zip"

7. deploy-web.zip contains at least one .ascx file per web project (--saas only, skip if no C# projects):
   Add-Type -AssemblyName System.IO.Compression.FileSystem
   $z = [System.IO.Compression.ZipFile]::OpenRead("${repoRoot}\\Deployments\\${deployDate}\\deploy-web.zip")
   $ascxCount = ($z.Entries | Where-Object { $_.Name -like "*.ascx" }).Count
   $z.Dispose()
   $expectedAscx = ${projectsWithCs.length}
   if ($ascxCount -lt $expectedAscx) { Write-Error "VALIDATION FAILED: deploy-web.zip has $ascxCount .ascx file(s) but expected >= $expectedAscx (one per project). Views may be missing."; exit 1 }
   Write-Host "PASS: $ascxCount .ascx file(s) in deploy-web.zip"

8. deploy-web.zip contains CrispCustomizations.config (--saas only, skip if no C# projects):
   Add-Type -AssemblyName System.IO.Compression.FileSystem
   $z = [System.IO.Compression.ZipFile]::OpenRead("${repoRoot}\\Deployments\\${deployDate}\\deploy-web.zip")
   $hasConfig = ($z.Entries | Where-Object { $_.Name -eq "CrispCustomizations.config" }).Count -gt 0
   $z.Dispose()
   if (-not $hasConfig) { Write-Error "VALIDATION FAILED: CrispCustomizations.config missing from deploy-web.zip — OA will not load without it"; exit 1 }
   Write-Host "PASS: CrispCustomizations.config found in deploy-web.zip"

9. SQL file count in deploy-batch.zip matches gathered count:
   Add-Type -AssemblyName System.IO.Compression.FileSystem
   $z = [System.IO.Compression.ZipFile]::OpenRead("${repoRoot}\\Deployments\\${deployDate}\\deploy-batch.zip")
   $zippedSqlCount = ($z.Entries | Where-Object { $_.Name -like "*.sql" }).Count
   $z.Dispose()
   $expectedSql = ${gathered.flatMap(p => p.sqlFiles).length}
   if ($zippedSqlCount -lt $expectedSql) { Write-Error "VALIDATION FAILED: deploy-batch.zip has $zippedSqlCount .sql file(s) but gathered $expectedSql. SQL builder may have skipped files."; exit 1 }
   Write-Host "PASS: $zippedSqlCount/$expectedSql SQL files in deploy-batch.zip"

10. Git tag exists on remote (push succeeded):
    $remoteTag = git ls-remote --tags origin "refs/tags/deploy/${coordination.environment}/${deployDate}" 2>&1
    if (-not $remoteTag) { Write-Error "VALIDATION FAILED: tag deploy/${coordination.environment}/${deployDate} not found on remote — git push may have failed"; exit 1 }
    Write-Host "PASS: tag confirmed on remote"

11. README.md exists:
    Test-Path "${repoRoot}\\Deployments\\${deployDate}\\README.md"

12. deploy-state.json updated for ${coordination.environment}:
    $state = Get-Content "${repoRoot}\\deploy-state.json" -Raw | ConvertFrom-Json
    $env = $state."${coordination.environment}"
    if (-not $env -or $env.date -ne "${deployDate}") { Write-Error "VALIDATION FAILED: deploy-state.json not updated for ${coordination.environment} — expected date ${deployDate}, got $($env.date)"; exit 1 }
    Write-Host "PASS: deploy-state.json shows ${coordination.environment} = ${deployDate}"

Add this at the top of your PowerShell session:
Add-Type -AssemblyName System.IO.Compression.FileSystem

If any check FAILS: report "VALIDATION FAILED: [check name] — [what to fix]" and stop.
If all pass: report "VALIDATION PASSED — package deploy/${coordination.environment}/${deployDate} is complete."

Flag: ${flag}
Has C# projects: ${projectsWithCs.length > 0}
Total SQL files gathered: ${gathered.flatMap(p => p.sqlFiles).length}`,
  { phase: 'Validate', label: 'validate' }
)

return {
  status: 'complete',
  tag: `deploy/${coordination.environment}/${deployDate}`,
  date: deployDate,
  flag,
}
