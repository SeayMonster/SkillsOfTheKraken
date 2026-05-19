---
name: generate-deployment
description: >
  Generate a deployment package for the Blackhawk CKB SQL Server environment.
  Gathers all SQL and C# changes since the last deploy tag, orders them by
  dependency tier, produces a combined deploy script and README handoff package,
  commits, and tags. Use --saas for SaaS environments where files must be handed
  off to a deployment team. Use --direct when you have direct database access and
  want to execute immediately via sqlcmd.
---

# Generate Deployment Skill

## Overview

Invoke as:
```
/crisp-dev:generate-deployment --saas
/crisp-dev:generate-deployment --direct
```

Both flags produce identical SQL output. The difference:
- `--saas` — README instructs a deployment team. No execution.
- `--direct` — README instructs local execution. Claude confirms then runs via `sqlcmd`.

**Announce at start:** "I'm using the generate-deployment skill to build the deployment package."

---

## Step 1 — Find the baseline tag

Run:
```bash
git tag --list 'deploy/*' --sort=-version:refname | head -1
```

If a tag is returned (e.g. `deploy/2026-04-29`), use it as the baseline.

If no tag exists, stop and ask:
> "No deploy tag found. Should I diff from the initial commit, or would you like to set a baseline tag manually first?"

Do not proceed until the user answers.

---

## Step 2 — Get changed files

Run:
```bash
git diff --name-only <baseline-tag> HEAD
```

Partition the results into two buckets:

**SQL files** — any `.sql` file under these paths:
- `CKB.Database/ckbcustom/`
- `BHN.Pog.Converter/CXBHNPogConverter/SQL/`
- `FacingsAnalysisReportPlanningCycle/SQL/`
- `FacingsAnalysisReport/CXFacingsAnalysisReport/SQL/`
- `FloatingShelves/CXFloatingShelf/SQL/`
- Any other `**/SQL/**/*.sql` path

**C# files** — any `.cs` file. Group by project root (the folder containing the `.sln` or `.csproj`).

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

Build an ordered object list (used in both the script header and the README):
- One entry per SQL file: `{ number, schema.objectName, type, notes }`
- `type` = Tables / Data / Function / View / Stored Procedure
- `notes` = first non-empty line from the SQL file's leading `--` comment block that describes the change (skip lines like `-- Development :`, `-- Author :`, `-- Date :`, `-- Version`). If no useful comment exists, use the git commit message that last touched the file: `git log -1 --pretty=%s -- <file>`

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

<full contents of each tier-1 file, separated by GO>

-- --------------------------------------------------------
-- DATA
-- --------------------------------------------------------

<full contents of each tier-2 file, separated by GO>

-- --------------------------------------------------------
-- FUNCTIONS
-- --------------------------------------------------------

<full contents of each tier-3 file, separated by GO>

-- --------------------------------------------------------
-- VIEWS
-- --------------------------------------------------------

<full contents of each tier-4 file, separated by GO>

-- --------------------------------------------------------
-- STORED PROCEDURES
-- --------------------------------------------------------

<full contents of each tier-5 file, separated by GO>
```

Omit any section block (including its header comment) if there are no files in that tier.

---

## Step 5 — Generate the README

Create: `Deployments/<YYYY-MM-DD>/README.md`

**Overview paragraph:** Write 2–3 sentences summarizing what this deployment covers. Base it on the git commit messages since the baseline tag:
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
- `<changed .cs file>` — <one-line description from git commit message>

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

Report to the user: "Deployment package created and tagged as `deploy/<YYYY-MM-DD>`."

---

## Step 7 — Execute (`--direct` only)

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

If `sqlcmd` exits with a non-zero code, report: "Execution failed. Exit code: `<code>`. Last output line: `<line>`." Do not attempt to roll back.

If `sqlcmd` is not found on PATH, report: "`sqlcmd` not found. Install SQL Server command-line tools, or use `--saas` to skip execution."

---

## Edge Cases

| Scenario | Action |
|---|---|
| No deploy tag exists | Ask user before diffing from initial commit |
| No SQL changes, no C# changes | Stop: "No deployable changes found since `<tag>`" |
| No SQL changes but C# changed | Skip SQL script, README has only DLL section |
| No C# changes | Omit DLL section from README entirely |
| Tier-99 file exists | Include at end with WARNING comment; list in README Notes |
| Server/database not in CLAUDE.md | Ask before generating |
| `--direct` but sqlcmd not on PATH | Report error, suggest `--saas` |
