---
name: create-saas-deployment-package
description: >
  Generate a SaaS CKB deployment package. Reads _package-request.json from the
  portal. Always includes full SQL install for selected projects, documents
  baseline diffs in README, orchestrates multi-agent workflow, and produces
  deploy-web.zip + deploy-batch.zip (--saas) or commit only (--local).
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
2. **Baseline diffs for README only** — git diff since baseline populates **Changes Since Baseline**; diffs do not filter package contents.
3. **README must include:** Changes Since Baseline, SQL deployment paths, SQL Files Deployed (full install), Combined manual-deploy-fallback.sql Objects.
4. **Dedupe shared SQL objects** across projects (e.g. `cx_job_ins` once in manual-deploy-fallback.sql).

## Pre-flight checks

1. Validate flag is `--saas` or `--local`. If missing, ask the user (see above).

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

Optional deterministic path (SQL + README + ZIPs before guides):
```
& "{SKILL_DIR}/scripts/build-deployment-package.ps1" -RepoRoot "<repoRoot>" -Flag "<flag>"
```

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
