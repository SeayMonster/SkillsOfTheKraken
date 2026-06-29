---
name: kraken-cursor-create-saas-deployment-package
description: >-
  Cursor adapter for SaaS CKB deployment packages. Reads _package-request.json,
  always includes full SQL install for selected projects, documents baseline diffs
  in README, and produces deploy-web.zip + deploy-batch.zip (--saas). Use when
  the user asks for a SaaS deployment package, kraken-cursor deployment, or
  create-saas-deployment-package in Cursor.
---

# kraken-cursor: create-saas-deployment-package

**Announce at start:** "I'm using kraken-cursor-create-saas-deployment-package to build the deployment package."

This skill replaces Claude Code's `Workflow()` with **Task subagents** and/or the **build script**. Do not call `Workflow()`.

## Core rules

1. **Always full SQL install** — gather every `*.sql` under each selected project's `SQL/` folder (exclude `Tests/`, `Old procs/`, `.vs/`). Do **not** limit SQL to git diff. Treat every run as a new installation.
2. **Baseline diffs for README only** — use git diff since baseline for a **Changes Since Baseline** section (SQL + C# + other). Diffs do not filter what goes into the package.
3. **README must include:**
   - **Changes Since Baseline** — per project; list changed files (omit section body if none)
   - **SQL Files Deployed (full install)** — complete table of every SQL file per project
   - **Combined deploy.sql Objects** — deduplicated objects in deploy script order
4. **Dedupe shared objects** — if two projects define the same object (e.g. `cx_job_ins`), include once in `deploy.sql` (first project in `_package-request.json` order wins).

## Invoke

**Flag:** `--saas` (default) or `--local`. If missing, ask before proceeding.

## Pre-flight (stop on failure)

1. Validate flag is `--saas` or `--local`.
2. Read `{repoRoot}/_package-request.json` — require `projects`, `environment`.
3. Read `{repoRoot}/Environment Details/env-config.json` — require entry for `environment`.
4. Resolve `SKILL_DIR` (this skill's folder) and `TEMPLATE_PATH`.

## Preferred execution (Cursor)

Run the build script (deterministic SQL + README + ZIPs):

```powershell
& "{SKILL_DIR}\scripts\build-deployment-package.ps1" -RepoRoot "{repoRoot}" -Flag "--saas"
```

Then run **Guides** phase (component `.md` files + Excel) via Task subagents if not added to script yet.

## Manual orchestration (fallback)

Use `references/workflow-phases.md` with Task subagents. Same rules apply: full SQL inventory, diff-aware README.

| Phase | Notes |
|-------|-------|
| Coordinate | baseline, env, server, db, date |
| Gather | **all SQL** + changed files since baseline |
| Build | deploy.sql + README (with diff + SQL list sections) |
| Commit | only if user asked |
| Guides | per-project `.md` + Excel |
| Package | stage-web + stage-batch ZIPs |

**Do not stop** when baseline diff is empty — SQL-only reinstall packages are valid.

## Output (--saas)

- `{repoRoot}/Deployments/{date}/deploy.sql`
- `{repoRoot}/Deployments/{date}/README.md`
- `{repoRoot}/Deployments/{date}/deploy-web.zip`
- `{repoRoot}/Deployments/{date}/deploy-batch.zip`

## Commit policy

Commit/tag/push **only** if the user explicitly requested it in the same message.

## Related

- Claude Code: `/kraken:create-saas-deployment-package --saas`
- Phase prompts: `references/workflow-phases.md`
- Build script: `scripts/build-deployment-package.ps1`
