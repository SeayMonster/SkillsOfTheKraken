---
name: create-saas-deployment-package
description: >
  Generate a SaaS CKB deployment package. Reads _package-request.json from the
  portal. Always includes full SQL install for selected projects, documents
  baseline diffs in README, and produces deploy-web.zip + deploy-batch.zip
  (--saas) or commit only (--local).
---

<context>
Invoke as:
```
/kraken:create-saas-deployment-package --saas
/kraken:create-saas-deployment-package --local
```

If invoked without a flag, ask: "Which mode? `--saas` (generate ZIP handoff package for deployment team) or `--local` (commit and push only — portal handles local deploy)?" Do not proceed until the user specifies.

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

1. Validate flag is `--saas` or `--local`. If missing, ask the user (see above).

2. Read `_package-request.json` from the repo root. Stop if:
   - File missing → "`_package-request.json` not found. Generate it from the portal before running this skill."
   - `projects` empty or missing → "No projects selected. Choose at least one project in the portal."
   - `environment` missing or null → "`environment` is required in `_package-request.json`."

3. Read `Environment Details/env-config.json`. If no entry matches the `environment` value from `_package-request.json`, stop:
   "`env-config.json` has no entry for `[environment value]`. Add server/database details first."

4. Determine the absolute path to the current repo root (the directory containing `_package-request.json`).

5. Announce: "Using create-saas-deployment-package skill..."

6. **Phase: Build** — run the PS1 directly via PowerShell tool. Report output. Fail hard if any exception.

```powershell
& "C:\Users\bseay\source\repos\SkillsOfTheKraken\skills\create-saas-deployment-package\scripts\build-deployment-package.ps1" -RepoRoot "<repoRoot>" -Flag "<flag>" -Phase "Stage"
```

7. **Phase: Validate** — spawn an Agent (NOT a Workflow) to check the staged SQL files:

```
Agent({
  description: "Validate staged SQL for cx_call_sql compatibility",
  prompt: "Read all *.sql files in <repoRoot>/Deployments/<today>/stage-batch/SQL/. Check each for: standalone GO lines, SET ANSI_NULLS, SET QUOTED_IDENTIFIER, USE <database>. Comments before CREATE/ALTER are fine. Report passed=true if clean, or list every problem file with the exact issue and fix."
})
```

If the agent reports any issues, stop. Do NOT run Phase Package. Print the issues clearly and ask the user to fix the source SQL files.

8. **Phase: Package** — only if Validate passed. Run PS1 directly:

```powershell
& "C:\Users\bseay\source\repos\SkillsOfTheKraken\skills\create-saas-deployment-package\scripts\build-deployment-package.ps1" -RepoRoot "<repoRoot>" -Flag "<flag>" -Phase "Zip"
```

Report final output verbatim.

## Post-package cleanup

After ZIPs are created successfully, remove transient files (build script does this automatically):

| Remove | Why |
|--------|-----|
| `Deployments/{date}/stage-web/` | Staging only — contents are in `deploy-web.zip` |
| `Deployments/{date}/stage-batch/` | Staging only — contents are in `deploy-batch.zip` |
| `_package-request.json` (repo root) | Portal IPC trigger — gitignored, do not leave after run |
| `.kraken-cursor/deploy-state-working.json` | Cursor workflow scratch state |

**Keep** in `Deployments/{date}/`: `README.md`, `manual-deploy-fallback.sql`, `deploy-web.zip`, `deploy-batch.zip`, component `*.md` guides, `Deployment Guide.xlsx`.

Web staging excludes Debug `bin/` when `bin/Release/` exists; never packages `.pdb` or `.vshost.*` DLLs.
</task>

<constraints>
| Scenario | Action |
|---|---|
| No flag provided | Ask before proceeding |
| `_package-request.json` missing | Stop with message |
| `projects` empty | Stop with message |
| `environment` missing | Stop with message |
| env not in env-config.json | Stop with message showing actual value |
| No SQL files for selected projects | Stop — nothing to deploy |
| Empty baseline diff | Continue — full SQL reinstall is valid |
</constraints>
