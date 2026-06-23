---
name: create-deployment-package
description: >
  Generate a deployment package for the CKB SQL Server environment.
  Gathers all SQL and C# changes since the last deploy tag, orders them by
  dependency tier, produces a combined deploy script and README handoff package,
  commits, and tags. Use --saas for SaaS environments where files must be handed
  off to a deployment team. Use --direct when you have direct database access and
  want to execute immediately via sqlcmd.
---

<context>
Invoke as:
```
/crisp-dev:generate-deployment --saas
/crisp-dev:generate-deployment --direct
```

If invoked without a flag, ask: "Which mode? `--saas` (generate handoff package, no execution) or `--direct` (generate and execute via sqlcmd)?" Do not proceed until the user specifies.

Both flags produce identical SQL output. The difference:
- `--saas` — README instructs a deployment team. No execution.
- `--direct` — README instructs local execution. Claude confirms then runs via `sqlcmd`.

**Announce at start:** "I'm using the generate-deployment skill to build the deployment package."
</context>

<task>
## Step 1 — Determine the baseline

First, check whether `_package-request.json` exists in the repo root and contains a `baseline` field:

```bash
cat _package-request.json
```

**If `baseline` is a non-null string** (e.g. `"deploy/Dev/2026-06-23"`):
Use it directly as the diff base. Skip the tag lookup below.

**If `baseline` is `null` or `_package-request.json` has no `baseline` field:**
Read `environment` from `_package-request.json` (e.g. `"Dev"`). Run:
```bash
git tag --list "deploy/<environment>/*" --sort=-version:refname | head -1
```

If a tag is returned, use it as the baseline.

If no tag exists, stop and ask:
> "No deploy tag found for `<environment>`. Should I diff from the initial commit, or would you like to set a baseline tag manually first?"

Do not proceed until the user answers.

If the user chooses "diff from initial commit", run:
```bash
git rev-list --max-parents=0 HEAD
```
Use the returned SHA as the baseline. Proceed to Step 2.

---

## Step 2 — Get changed files

Run:
```bash
git diff --name-only <baseline-tag> HEAD
```

Partition the results into two buckets:

**SQL files** — any `.sql` file under these paths:
- `CKB.Database/ckbcustom/`
- `FacingsAnalysisReportPlanningCycle/SQL/`
- `FacingsAnalysisReport/CXFacingsAnalysisReport/SQL/`
- `FloatingShelves/CXFloatingShelf/SQL/`
- Any other `**/SQL/**/*.sql` path

**C# files** — any `.cs` file. Group by project root. Use the nearest ancestor folder that contains a `.sln` file. If no `.sln` exists, fall back to the nearest ancestor containing a `.csproj`. If multiple `.cs` files share the same project root, group them together under one DLL section.

**Ignore entirely:**
- `.md`, `.csproj`, `.sqlproj`, `.sln`, `.json`, `.ps1`, `.html`
- Anything under `Deployments/`, `docs/`, `.claude/`

If both buckets are empty, stop and report: "No deployable changes found since `<baseline-tag>`."

---

## Step 3 — Categorize and sort SQL files

Assign each SQL file a tier based on its path. Sort within each tier alphabetically.

| Tier | Match rule |
|---|---|
| 1 — Tables | Path contains `Tables/` AND filename does NOT start with `Populate` or `ckbcustom.Populate` |
| 2 — Data | Filename starts with `Populate` or `ckbcustom.Populate` |
| 3 — Functions | Path contains `Functions/` |
| 4 — Views | Path contains `Views/` |
| 5 — Stored Procedures | Path contains `Stored Procedures/` or `Store Procedures/` or `Procedures/` |
| 99 — Unknown | Anything that does not match tiers 1–5 |

**Precedence rule:** When a file matches multiple tiers (e.g. a file named `Populate_foo.sql` inside a `Stored Procedures/` folder), the filename-based rules (tier 2) take priority over path-based rules (tier 5).

For tier 99 files, include them at the end of the script with this comment preceding the file contents:
```sql
-- WARNING: unrecognized path — verify ordering manually
-- File: <path>
```

---

## Step 4 — Build the SQL script

Read server and database from the `CLAUDE.md` in the repo root. Look for a line matching `Server:` and `Database:` in the `## CKB Database` section. If not found, ask the user for both values before continuing.

Create the output file at: `Deployments/<YYYY-MM-DD>/deploy_<YYYY-MM-DD>.sql`

Use today's date for `YYYY-MM-DD`.

Before concatenating each SQL file, strip the following patterns from the file contents:
- Any line that is exactly `USE <any_database_name>` followed by `GO` (removes duplicate USE statements)
- Any leading standalone `GO` lines at the top of the file
- Any trailing standalone `GO` lines at the bottom of the file (the concatenation step adds its own GO after each file)

Build an ordered object list (used in both the script header and the README):
- One entry per SQL file: `{ number, schema.objectName, type, notes }`
- `type` = Tables / Data / Function / View / Stored Procedure
- `notes` = first non-empty line from the SQL file's leading `--` comment block that describes the change (skip lines like `-- Development :`, `-- Author :`, `-- Date :`, `-- Version`). If no non-header comment line exists in the file's leading block (all lines match the skip patterns or the block is absent), use the git commit message that last touched the file: `git log -1 --pretty=%s -- <file>`

Write the file with this structure:

```sql
-- ============================================================
-- Deployment: YYYY-MM-DD
-- Target:     <server>  |  Database: <database>
-- Run in:     SSMS — safe to re-run (all CREATE OR ALTER)
-- ============================================================
-- 1. ckbcustom.<object>   <type>   <notes>
-- 2. ...
-- ============================================================

USE <database>
GO

-- --------------------------------------------------------
-- TABLES
-- --------------------------------------------------------

<full contents of each tier-1 file>

-- --------------------------------------------------------
-- DATA
-- --------------------------------------------------------

<full contents of each tier-2 file>

-- --------------------------------------------------------
-- FUNCTIONS
-- --------------------------------------------------------

<full contents of each tier-3 file>

-- --------------------------------------------------------
-- VIEWS
-- --------------------------------------------------------

<full contents of each tier-4 file>

-- --------------------------------------------------------
-- STORED PROCEDURES
-- --------------------------------------------------------

<full contents of each tier-5 file>
```

> **GO placement:** After concatenating each file's contents, append a standalone `GO` on its own line. This applies after every file, including the last file in each tier. Example:
> ```sql
> -- file 1 contents --
> GO
> -- file 2 contents --
> GO
> ```

Omit any section block (including its header comment) if there are no files in that tier.

---

## Step 5 — Generate the README

Create: `Deployments/<YYYY-MM-DD>/README.md`

**Overview paragraph:** Write 2–3 sentences using this template: "This deployment covers [brief list of changed areas, e.g. 'stored procedure updates to cx_facings_analysis_report and cx_automator_process']. [One sentence on the main functional change, derived from commit messages.] [If a table changed: 'The cx_X table is recreated — verify existing rows are preserved if needed.']" Base the content on the git commit messages since the baseline tag:
```bash
git log <baseline-tag>..HEAD --pretty="%s"
```

**SQL deployment table:**

For `--saas`, Step 1 reads:
```markdown
## Step 1 — Send to deployment team
Provide `deploy_YYYY-MM-DD.sql` to the team with access to the target environment.
They should run it in SSMS against **<database>** on **<server>**. The script is safe to re-run.
```

For `--direct`, Step 1 reads:
```markdown
## Step 1 — Run SQL Script in SSMS
**File:** `deploy_YYYY-MM-DD.sql`
Run against **<database>** on **<server>**. The script is safe to re-run (CREATE OR ALTER on all procs, DROP/CREATE on tables).
```

After Step 1, include the object table:
```markdown
**What it deploys (in order):**
| # | Object | Type | Notes |
|---|--------|------|-------|
| 1 | `ckbcustom.cx_conv_prod_key_mappings` | Table | ... |
```

**DLL section** — only include if `.cs` files changed. One subsection per affected project. Derive project name from the `.sln` filename or the parent folder name. Number steps sequentially after the SQL step.

```markdown
## Step N — Build and Deploy: <ProjectName>
**Solution:** `<relative path to .sln>`

**Changes:**
- `<changed .cs file>` — <subject line from `git log -1 --pretty=%s -- <file>` for that specific file>

**Steps:**
1. Open solution in Visual Studio
2. Set configuration to **Release** / **x86**
3. Build solution
4. Copy output from `<project>/bin/Release/` to the target environment
```

**Notes section** — include if any tier-99 files exist:
```markdown
## Notes
- The following files had unrecognized paths and were appended at the end of the script. Verify their ordering is correct before running:
  - `<path>`
```

---

## Step 6 — Commit and tag

Stage and commit the deployment folder:
```bash
git add Deployments/<YYYY-MM-DD>/
git commit -m "Add <YYYY-MM-DD> deployment package"
```

Then create the deploy tag:
```bash
git tag deploy/<YYYY-MM-DD>
```

---

## Step 7 — Generate deployment guides

This step runs for both `--saas` and `--direct` flags.

### 7a — Read the global template

Read the file at:
```
C:\Users\bseay\source\repos\SkillsOfTheKraken\skills\create-deployment-package\templates\deployment-guide-template.md
```

If the file does not exist, report: "Deployment guide template not found at expected path — skipping guide generation." Continue to Step 8 without failing.

### 7b — Identify components

Using the file buckets from Step 2, group changes into components:

| Component | What it covers |
|---|---|
| One per C# project that changed | All `.cs` files grouped by project root (nearest `.sln` or `.csproj`) + any `.sql` files under that project's `**/SQL/**` subfolder |
| `CKB Database` | All `.sql` files under `CKB.Database/` that are not inside any C# project subfolder |

If no C# projects changed and no `CKB.Database/` SQL changed, skip to 7d (no component guides to generate).

### 7c — Generate one markdown file per component

For each component, produce a populated `.md` by replacing every `{{token}}` in the template:

**`{{component_name}}`** — project name from `.sln` filename (without extension) or parent folder name. For the SQL-only component, use `CKB-Database`.

**`{{date}}`** — today's date as `YYYY-MM-DD`.

**`{{brief_description}}`** — run:
```bash
git log <baseline-tag>..HEAD --pretty="%s" -- <all files in this component> | head -1
```
Format as: `[ComponentName]: [commit subject]`

**`{{implementation_steps}}`** — build from what changed in this component:

If SQL objects exist for this component:
```
1. Run `deploy_<YYYY-MM-DD>.sql` in SSMS against **ckb** on **cx-lpt943\v2022**. The script is safe to re-run.
```

If `.cs` files changed for this component (DLLs needed), append a numbered step after the SQL step (or start at 1 if no SQL step):
```
N. Copy to target JDA environment:
   - <dll_filename_1>
   - <dll_filename_2>
   ...
```

List every `.dll` and `.dll.config` file found in `<project_root>/bin/Release/`. If `bin/Release/` doesn't exist yet (not built), list only the main project DLL: `<ProjectName>.dll`.

**`{{code_drop}}`** — build from the object list computed in Steps 3–4:

```
SQL (in deploy_<YYYY-MM-DD>.sql):
  Tables:
    - ckbcustom.<table_name>
  Functions:
    - ckbcustom.<function_name>
  Views:
    - ckbcustom.<view_name>
  Stored Procedures:
    - ckbcustom.<proc_name>

DLLs (from <project_root>/bin/Release/):
  <dll_filename_1>
  <dll_filename_2>
```

Omit the SQL block if no SQL objects for this component. Omit any tier sub-section (Tables, Functions, etc.) if empty. Omit the DLLs block if no C# changes for this component.

**`{{rollback_steps}}`** — generate per object type present in this component:

- If any Tables exist: `Back up <table_name> before running.`
- If Stored Procedures, Functions, or Views exist: `SQL uses CREATE OR ALTER — no rollback needed.`
- If DLLs exist: `Restore previous <ProjectName>.dll from backup in the target JDA environment.`

**`{{business_justification}}`** — leave blank (empty string).

**Output path:** `Deployments/<YYYY-MM-DD>/<component_name>.md`

Use today's date. Replace spaces in component name with hyphens, lowercase.

Write the file using the Write tool (or equivalent).

### 7d — Generate Excel deployment guide

Using the component data from 7c, run the following PowerShell script. Construct the `$rows` array by substituting the actual token values you computed above — one hashtable entry per component.

```powershell
$date = '<YYYY-MM-DD>'
$outputPath = "Deployments\$date\Deployment Guide $date.xlsx"

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

# Substitute real values — one hashtable per component
$rows = @(
    @{
        BriefDescription = "<ComponentName>: <brief>"
        ImplementSteps   = "<implementation steps text>"
        RollbackSteps    = "<rollback steps text>"
        VerifySteps      = ""
        CodeDrop         = "<code drop text>"
        TestResults      = "Pending UAT"
        CustApproval     = "Pending"
        Timeslot         = ""
        BizJustification = ""
    }
    # Add one hashtable per additional component
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
$fullPath = (Resolve-Path ".\").Path + "\" + $outputPath
$wb.SaveAs($fullPath)
$wb.Close($false)
$excel.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
Write-Output "Excel saved: $fullPath"
```

If the script fails with a COM error (e.g., Excel not installed), report: "Excel generation failed: `<error message>`. Markdown guides were generated successfully." Continue to 7e without failing.

### 7e — Commit guides and push

Stage the generated guide files:
```bash
git add "Deployments/<YYYY-MM-DD>/"
git commit -m "Add deployment guides for <YYYY-MM-DD>"
```

Push the Blackhawk repo (commit + tag from Step 6 push together):
```bash
git push
git push origin deploy/<YYYY-MM-DD>
```

Push the SkillsOfTheKraken repo if the template file is new or modified:
```powershell
Set-Location 'C:\Users\bseay\source\repos\SkillsOfTheKraken'
git status
```

If the template file appears as modified or untracked:
```powershell
git add 'skills/create-deployment-package/templates/deployment-guide-template.md'
git commit -m "Add deployment guide markdown template"
git push
```

If `C:\Users\bseay\source\repos\SkillsOfTheKraken` does not exist, report: "SkillsOfTheKraken repo not found — skipping Kraken push." Do not fail the deployment.

Report to the user: "Deployment package created and tagged as `deploy/<YYYY-MM-DD>`. Guides saved to `Deployments/<YYYY-MM-DD>/`."

---

## Step 8 — Execute (`--direct` only)

Present this confirmation before doing anything:
```
About to execute deploy_<YYYY-MM-DD>.sql
  Server:   <server>
  Database: <database>
  File:     Deployments/<YYYY-MM-DD>/deploy_<YYYY-MM-DD>.sql

Confirm? (yes / no)
```

Wait for an explicit "yes" from the user. Do not proceed on anything ambiguous.

On confirmation, run:
```bash
sqlcmd -S <server> -d <database> -E -i "Deployments/<YYYY-MM-DD>/deploy_<YYYY-MM-DD>.sql"
```

`-E` = Windows Integrated Authentication.

Show the full `sqlcmd` output to the user.

If `sqlcmd` exits with a non-zero code, report: "Execution failed. Exit code: `<code>`. Last output line: `<line>`. The script uses CREATE OR ALTER and DROP/CREATE patterns — it is safe to re-run after fixing the reported error. Check the error in SSMS if needed before re-running." Do not attempt to roll back.

If `sqlcmd` is not found on PATH, report: "`sqlcmd` not found. Install SQL Server command-line tools, or use `--saas` to skip execution."
</task>

<constraints>
| Scenario | Action |
|---|---|
| No deploy tag exists | Ask user before diffing from initial commit |
| No SQL changes, no C# changes | Stop: "No deployable changes found since `<tag>`" |
| No SQL changes but C# changed | Skip SQL script, README has only DLL section |
| No C# changes | Omit DLL section from README entirely |
| Tier-99 file exists | Include at end with WARNING comment; list in README Notes |
| Server/database not in CLAUDE.md | Ask before generating |
| `--direct` but sqlcmd not on PATH | Report error, suggest `--saas` |
| Template file not found at Kraken path | Report warning, skip guide generation, continue |
| Excel COM error | Report warning, skip Excel, markdown guides still written |
</constraints>
