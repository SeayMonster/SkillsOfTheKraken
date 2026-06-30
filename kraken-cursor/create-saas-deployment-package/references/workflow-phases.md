# Workflow phases — kraken-cursor-create-saas-deployment-package

**Important:** Always assume a **full SQL installation**. Gather **all** `*.sql` files from each project's `SQL/` tree. Baseline git diff is for README **Changes Since Baseline** only.

Preferred in Cursor: run `scripts/build-deployment-package.ps1` instead of manual phases for SQL/README/ZIPs.

---

## Phase 1: Coordinate

(Same as before — resolve baseline, env, server, database, date, webTarget, batchTarget.)

---

## Phase 2: Gather (PARALLEL — one Task per project)

```
You are the Gather agent for project "{projectName}".

Repo root: {repoRoot}
Baseline: {baseline}

Steps:

### A. Full SQL inventory (ALWAYS — new install assumption)

Scan `{repoRoot}/{projectName}/SQL/` recursively for all `*.sql` files.
Exclude paths containing: `Tests/`, `Old procs/`, `.vs/`
Exclude zero-byte files.

Assign tier to each SQL file:
- Tier 1: path contains "Tables/" AND filename does NOT start with "Populate"
- Tier 2: filename starts with "Populate" or "ckbcustom.Populate"
- Tier 3: path contains "Functions/"
- Tier 4: path contains "Views/"
- Tier 5: path contains "Stored Procedures/" OR "Store Procedures/" OR "Procedures/"
- Tier 99: anything else (Types, Configuration, etc.)

Return ALL matching files in sqlFiles — not filtered by git diff.

### B. Changed files since baseline (for README diff section)

Run:
  git diff --name-only {baseline} HEAD -- {projectName}/
  git diff --name-only {baseline} -- {projectName}/
Merge and dedupe.

Partition changedFiles into changedSql (.sql), changedCs (.cs), changedOther.
Ignore: .md, .csproj, .sqlproj, .sln, .json, .ps1, .html, Tests/, Old procs/, Deployments/, docs/, .claude/

### C. Return JSON

{
  projectName, projectRoot: "{projectName}/",
  sqlFiles: [{path, tier}],           // FULL inventory
  changedFiles: [...],                 // all changed paths
  changedSql: [...], changedCs: [...],
  csFiles: [{path}] from changedCs,   // for web deploy steps
  hasSql: sqlFiles.length > 0,
  hasChanges: changedFiles.length > 0
}
```

Parent: merge into `projects` array (NOT filtered to hasChanges only). Dedupe shared SQL objects at Build time.

**Never stop with `no-changes`** — if sqlFiles exist for any selected project, continue.

---

## Phase 3: Build

### 3a SQL Builder

- Merge sqlFiles from ALL projects; dedupe by object name (lowercase)
- Sort tier asc, path asc
- Write manual-deploy-fallback.sql (see build script for strip/grant rules)

### 3b README Builder

README **required sections** (in order):

1. **Overview** — full SQL install for listed projects
2. **SQL deployment paths** — table + explanation:
   - Automated: `SQL/01_*.sql` … via `Deploy-SQL.ps1` (normal)
   - Manual: `manual-deploy-fallback.sql` at batch zip root for SSMS (not under `SQL/` — avoids double deploy)
   - Use one path, not both; same deduplicated object count
3. **Changes Since Baseline** — per project:
   - If no changes: "No file changes since `{baseline}`."
   - Else: bullet lists for changed SQL, C# (with `git log -1 --pretty=%s`), other
4. **SQL Files Deployed (full install)** — per project table:
   | # | File | Tier | Type |
   - Every file from sqlFiles inventory
5. **Combined manual-deploy-fallback.sql Objects** — table matching combined script header order
6. **Step 1 / Step 2** — batch (Deploy-SQL.ps1, SQL/ only) + optional SSMS fallback note + web deploy instructions
7. **Step N** — per project with csFiles (web deploy)

---

## Phases 4–6

Unchanged from prior version (Commit optional, Guides parallel, Package creates deploy-web.zip + deploy-batch.zip with numbered SQL/ files in stage-batch/SQL/).

Batch staging: copy **individual source SQL files** (not manual-deploy-fallback.sql split) as `01_filename.sql`, `02_...`, tier sort order. Also copy `manual-deploy-fallback.sql` to batch zip root for SSMS fallback (not under `SQL/` — `Deploy-SQL.ps1` only runs `SQL/*.sql`).

---

## Phase 7: Cleanup (after Package — parent or Package agent)

Run immediately after ZIPs succeed. **Do not commit** staging folders or `_package-request.json`.

```powershell
$deployDir = "{repoRoot}/Deployments/{date}"
Remove-Item "$deployDir/stage-web", "$deployDir/stage-batch" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "{repoRoot}/_package-request.json" -Force -ErrorAction SilentlyContinue
Remove-Item "{repoRoot}/.kraken-cursor/deploy-state-working.json" -Force -ErrorAction SilentlyContinue
```

**Keep in deploy folder:** README.md, manual-deploy-fallback.sql, deploy-web.zip, deploy-batch.zip, component `*.md`, Deployment Guide.xlsx.

**Web staging rules:** prefer `bin/Release/`; skip `bin/Debug/` when Release exists; never stage `.pdb` or `.vshost.*`.

---

## Deploy-Web.ps1 / Deploy-SQL.ps1 templates

(See end of previous version — unchanged.)
