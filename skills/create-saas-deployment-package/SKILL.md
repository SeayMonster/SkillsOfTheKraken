---
name: create-saas-deployment-package
description: >
  Generate a SaaS CKB deployment package for any client repo. Reads
  _package-request.json from the Deployment Portal and the repo's client.json.
  Builds Deployments/<release>/<NN>_<HHmm>/ with full SQL install, deploy-web.zip,
  deploy-batch.zip (self-contained Deploy-SQL.ps1 with backup, rollback and
  cx_deploy_log) and deploy-sapro.zip when the repo has SA Pro scripts.
  Environment-agnostic: one package goes to Test, then Prod.
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
5. **Strip GO from batch SQL** -- numbered `SQL/` files run one batch each through ADO.NET in the package's own `Deploy-SQL.ps1`. Strip all standalone `GO` lines with `Clean-SqlContent`. Keep `GO` in `manual-deploy-fallback.sql` (SSMS).
6. **Extract GRANT for batch SQL** — peel trailing `GRANT` into `{NN}_grants.sql` via `Extract-Grants`. GRANTs inside `IF NOT EXISTS` table blocks stay in the body.
7. **Validate batch SQL before ZIP** — `build-deployment-package.ps1` runs `Test-BatchSqlFiles` and fails if `GO` or post-`END` `GRANT` remain. No live-database test agent; static validation only.
8. **Release and build** -- output goes to `Deployments/<release>/<NN>_<HHmm>/`. Builds are numbered within the release; a same-day patch is the next build. After the zips are made the commit is tagged `deploy/<release>_<NN>`, `deploy-state.json` records it as the next baseline, and `Deployments/<release>/README.md` lists every build newest first. No `deploy/*` tag at all means a first run: full install, README says "Initial package".
9. **Deploy-time safety** -- `deploy-batch.zip` ships `Deploy-SQL.ps1`, `Rollback.ps1`, `DeployLib.ps1`, `cx_deploy_log.sql` and `manifest.json`. `Deploy-SQL.ps1` logs to `ckbcustom.cx_deploy_log`, backs up every touched object into `Backup\<time>\` before running SQL, and stops if the backup fails. `Rollback.ps1` restores newest build first.
10. **Deploy locations** -- `client.json` `targets.web|batch|sapro.saas` (and a batch or SA Pro project's `deployTo`) become the defaults of `Deploy-Web.ps1`, `Deploy-Exe.ps1` and `Deploy-SaPro.ps1`, and the README's "Where things go" table.
11. **Standard SQL** -- `templates/sql/` (`ckbcustom.cx_log`, `cx_log_ins`, `cx_log_purge`) ships in every package, after the selected projects' SQL; a project's own copy of the same object wins. LogWriter in each project writes `cx_log` and purges its own `Source` with `LogRetentionDays` (default 30) from the DLL's config.

## Pre-flight checks

1. Determine flag: use provided `--saas` or `--local`. If missing, default to `--saas`.

2. Read `_package-request.json` from the repo root. Stop if:
   - File missing -> "`_package-request.json` not found. Generate it from the Deployment Portal before running this skill."
   - `projects` empty or missing -> "No projects selected. Choose at least one project in the portal."
   `release` (YYYY-MM-DD) is optional and defaults to today; `environment` and `baseline` are optional.

3. Read `client.json` if present (project paths, `webDlls`, `vendorWebDlls`, `targets`). Every key is optional; without it the package is built exactly as before. `Environment Details/env-config.json` is optional and only names a server in the README.

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
| `Deployments/{release}/{build}/stage-web/` | Staging only — contents are in `deploy-web.zip` |
| `Deployments/{release}/{build}/stage-batch/` | Staging only — contents are in `deploy-batch.zip` |
| `Deployments/{release}/{build}/stage-sapro/` | Staging only — contents are in `deploy-sapro.zip` (omitted when no SA Pro scripts) |
| `_package-request.json` (repo root) | Portal IPC trigger — gitignored, do not leave after run |
| `_package-build.json` (repo root) | Stage-to-Zip handoff of the build folder |
| `.kraken-cursor/deploy-state-working.json` | Cursor workflow scratch state |

**Keep** in `Deployments/{release}/{build}/`: `README.md`, `manifest.json`, `manual-deploy-fallback.sql`, `deploy-web.zip`, `deploy-batch.zip`, `deploy-sapro.zip` (if produced). `Deployments/{release}/README.md` is regenerated each build.

**SA Pro (`deploy-sapro.zip`):** projects whose `.csproj` references `JDA.Intactix.Automation`. Flat layout of `<AssemblyName>.dll` + the **built** `<AssemblyName>.dll.config` from `bin\Release` — never the source `App.config`, since every project names that file identically and copying source would collapse them into one. With `client.json` `targets.sapro` set, the zip ships `Deploy-SaPro.ps1` defaulting to that location (a project's `deployTo` overrides); without it the files are copied by hand into the client's Space Automation script directory. Their SQL stays in `deploy-batch.zip` (the DB credentials only exist on the batch server).

Every selected project (except client.json `skip` and SQL-only projects) is built in Release with MSBuild before staging, so the package never ships a stale or missing `binRelease`. Web staging excludes Debug `bin/` when `bin/Release/` exists; never packages `.pdb` or `.vshost.*` DLLs.
</task>

<constraints>
| Scenario | Action |
|---|---|
| No flag provided | Default to `--saas`, never ask |
| `_package-request.json` missing | Stop with message |
| `projects` empty | Stop with message |
| No SQL files for selected projects | Stop — nothing to deploy |
| Empty baseline diff | Continue — full SQL reinstall is valid |
| No `deploy/*` tag at all | First run: full install, README says "Initial package" |
| Validate phase | Agent call ONLY — `-Phase Validate` does NOT exist in the PS1 (ValidateSet = `All,Stage,Zip`). Never pass Validate to the script. |
| `Manual Scripts/` or `Manual/` folder in project SQL | Copied to `stage-batch/Manual Scripts/` as-is — NOT numbered, NOT run by `Deploy-SQL.ps1`. Excluded from `Get-AllSqlFiles` automatically. |
</constraints>
