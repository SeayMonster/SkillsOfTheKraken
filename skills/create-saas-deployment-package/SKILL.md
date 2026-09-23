---
name: create-saas-deployment-package
description: >
  Generate a SaaS CKB deployment package. Reads _package-request.json from the
  portal. Always includes full SQL install for selected projects, documents
  baseline diffs in README, and produces deploy-web.zip + deploy-batch.zip
  (+ deploy-sapro.zip when the repo has SA Pro scripts)
  (--saas) or commit only (--local).
---

<context>
Invoke as:
```
/kraken:create-saas-deployment-package --saas
/kraken:create-saas-deployment-package --local
```

**Default flag: `--saas`** — if invoked without a flag, proceed with `--saas`. Local deployments are handled via the portal; never ask.

**Announce at start:** "I'm using the create-saas-deployment-package skill to build the deployment package."
</context>

<task>
## Core rules

1. **Always full SQL install** — gather every `*.sql` under each selected project's `SQL/` folder (exclude `Tests/`, `Old procs/`, `.vs/`). Do not limit SQL to git diff. Treat every run as a new installation.
   - **`SQL/Cleanup/` folder (tier -1)** — DROP scripts for objects removed from this project. These run *before* all other SQL tiers so dead objects are gone before any CREATE OR ALTER runs. Use safe `IF EXISTS` guards. Add one here whenever a proc, view, or type is deleted from the project.
2. **Baseline diffs for README only** — git diff since baseline populates **Changes Since Baseline**; diffs do not filter package contents.
3. **README must include:** Changes Since Baseline, SQL deployment paths, SQL Files Deployed (full install), Combined manual-deploy-fallback.sql Objects.
4. **Dedupe shared SQL objects** across projects (e.g. `cx_job_ins` once in manual-deploy-fallback.sql).
5. **Strip GO from batch SQL** — numbered `SQL/` files run via `cx_call_sql.ps1` (ADO.NET). Strip all standalone `GO` lines with `Clean-SqlContent`. Keep `GO` in `manual-deploy-fallback.sql` (SSMS).
6. **Extract GRANT for batch SQL** — peel trailing `GRANT` into `{NN}_grants.sql` via `Extract-Grants`. GRANTs inside `IF NOT EXISTS` table blocks stay in the body.
7. **Validate batch SQL before ZIP** — `build-deployment-package.ps1` runs `Test-BatchSqlFiles` and fails if `GO` or post-`END` `GRANT` remain. No live-database test agent; static validation only.

## Pre-flight checks

1. Determine flag: use provided `--saas` or `--local`. If missing, default to `--saas`.

2. Read `_package-request.json` from the repo root. Stop if:
   - File missing → "`_package-request.json` not found. Generate it from the portal before running this skill."
   - `projects` empty or missing → "No projects selected. Choose at least one project in the portal."
   - `environment` missing or null → "`environment` is required in `_package-request.json`."

3. Read `Environment Details/env-config.json`. If no entry matches the `environment` value from `_package-request.json`, stop:
   "`env-config.json` has no entry for `[environment value]`. Add server/database details first."

4. Determine the absolute path to the current repo root (the directory containing `_package-request.json`).

5. Announce: "Using create-saas-deployment-package workflow..."

6. Invoke the Workflow:

```
Workflow({
  scriptPath: "C:\\Users\\bseay\\source\\repos\\SkillsOfTheKraken\\skills\\create-saas-deployment-package\\workflow.js",
  args: { flag: "<--saas or --local>", repoRoot: "<absolute path to repo root>" }
})
```

> **Do NOT run a pre-clean step on source files.** BOM and em-dash stripping is handled inside `Clean-SqlContent` in the build script during staging — modifying source files in-place has caused SQL corruption in the past.

Optional deterministic path (run all phases via PS1 directly):

```powershell
& "C:\Users\bseay\source\repos\SkillsOfTheKraken\skills\create-saas-deployment-package\scripts\build-deployment-package.ps1" -RepoRoot "<repoRoot>" -Flag "<flag>"
```

## Post-package cleanup

After ZIPs are created successfully, remove transient files (build script does this automatically):

| Remove | Why |
|--------|-----|
| `Deployments/{date}/stage-web/` | Staging only — contents are in `deploy-web.zip` |
| `Deployments/{date}/stage-batch/` | Staging only — contents are in `deploy-batch.zip` |
| `Deployments/{date}/stage-sapro/` | Staging only — contents are in `deploy-sapro.zip` (omitted when no SA Pro scripts) |
| `_package-request.json` (repo root) | Portal IPC trigger — gitignored, do not leave after run |
| `.kraken-cursor/deploy-state-working.json` | Cursor workflow scratch state |

**Keep** in `Deployments/{date}/`: `README.md`, `manual-deploy-fallback.sql`, `deploy-web.zip`, `deploy-batch.zip`, `deploy-sapro.zip` (if produced), component `*.md` guides, `Deployment Guide.xlsx`.

**SA Pro (`deploy-sapro.zip`):** projects whose `.csproj` references `JDA.Intactix.Automation`. Flat layout of `<AssemblyName>.dll` + the **built** `<AssemblyName>.dll.config` from `bin\Release` — never the source `App.config`, since every project names that file identically and copying source would collapse them into one. User-deployed: someone copies the files into the client's Space Automation script directory by hand, so the zip names no target and ships no PowerShell. Their SQL stays in `deploy-batch.zip` (`cx_call_sql.ps1` and the DB credentials only exist on the batch server).

Web staging excludes Debug `bin/` when `bin/Release/` exists; never packages `.pdb` or `.vshost.*` DLLs.
</task>

<constraints>
| Scenario | Action |
|---|---|
| No flag provided | Default to `--saas`, never ask |
| `_package-request.json` missing | Stop with message |
| `projects` empty | Stop with message |
| `environment` missing | Stop with message |
| env not in env-config.json | Stop with message showing actual value |
| No SQL files for selected projects | Stop — nothing to deploy |
| Empty baseline diff | Continue — full SQL reinstall is valid |
| Validate phase | Agent call ONLY — `-Phase Validate` does NOT exist in the PS1 (ValidateSet = `All,Stage,Zip`). Never pass Validate to the script. |
| `Manual Scripts/` or `Manual/` folder in project SQL | Copied to `stage-batch/Manual Scripts/` as-is — NOT numbered, NOT run by `Deploy-SQL.ps1`. Excluded from `Get-AllSqlFiles` automatically. |
</constraints>
