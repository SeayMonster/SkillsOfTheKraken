---
name: kraken-cursor-create-saas-deployment-package
description: >-
  Cursor adapter for SaaS CKB deployment packages. Reads _package-request.json,
  orchestrates multi-phase Task subagents (Coordinate, Gather, Build, Commit,
  Guides, Package), and produces deploy-web.zip + deploy-batch.zip (--saas) or
  commit-only (--local). Use when the user asks for a SaaS deployment package,
  kraken-cursor deployment, or create-saas-deployment-package in Cursor.
---

# kraken-cursor: create-saas-deployment-package

**Announce at start:** "I'm using kraken-cursor-create-saas-deployment-package to build the deployment package."

This skill replaces Claude Code's `Workflow()` with **Task subagents** and shell commands. Do not call `Workflow()`.

## Invoke

User request examples:
- "create saas deployment package"
- "kraken-cursor deployment --saas"
- "build deployment package for Automator and CXDerivedControls"

**Flag:** `--saas` (default) or `--local`. If missing, ask before proceeding.

## Pre-flight (parent agent — stop on failure)

1. Validate flag is `--saas` or `--local`.
2. Read `{repoRoot}/_package-request.json`. Stop if missing, empty `projects`, or missing `environment`.
3. Read `{repoRoot}/Environment Details/env-config.json`. Stop if no entry for `environment`.
4. Set `repoRoot` = directory containing `_package-request.json`.
5. Read `references/workflow-phases.md` in this skill folder for full phase prompts.
6. Resolve skill paths:
   - `SKILL_DIR` = directory containing this SKILL.md (installed at `~/.cursor/skills/kraken-cursor-create-saas-deployment-package/` or repo `kraken-cursor/create-saas-deployment-package/`)
   - `TEMPLATE_PATH` = `{SKILL_DIR}/templates/deployment-guide-template.md`
7. Create state file `{repoRoot}/.kraken-cursor/deploy-state-working.json` (empty `{}`) for phase handoff.

## Orchestration overview

Execute phases **in order**. Pass outputs forward via the state file and Task return values.

| Phase | Parallelism | Tool |
|-------|-------------|------|
| 1 Coordinate | single | Task (generalPurpose) or parent |
| 2 Gather | one Task per project | Task × N in one message |
| 3 Build | SQL + README | Task × 2 in one message |
| 4 Commit | single | Task or parent + Shell |
| 5 Guides | one per project + Excel | Task × (N+1) in one message |
| 6 Package | single | Task or parent + Shell |

**Early exit:** If Gather finds zero projects with changes, stop and report `no-changes`.

## Phase execution

For each phase, use the matching section in `references/workflow-phases.md`. Substitute:
- `{repoRoot}`, `{flag}`, `{deployDate}`, `{coordination}`, `{changedProjects}`, `{TEMPLATE_PATH}`

After **Coordinate**, write coordination JSON to:
`{repoRoot}/.kraken-cursor/deploy-state-working.json` → key `coordination`

After **Gather**, append key `changedProjects` (array).

After **Build**, verify files exist:
- `{repoRoot}/Deployments/{deployDate}/deploy.sql`
- `{repoRoot}/Deployments/{deployDate}/README.md`

## Commit policy

Phases 4 and 6 run git commit/push **only if the user explicitly asked to commit/push** in the same request. Otherwise stage files and report paths; ask before committing.

## Output (--saas)

Report full paths when complete:
- `{repoRoot}/Deployments/{deployDate}/deploy-web.zip`
- `{repoRoot}/Deployments/{deployDate}/deploy-batch.zip`
- `{repoRoot}/Deployments/{deployDate}/README.md`
- Tag (if created): `deploy/{environment}/{deployDate}`

## Constraints

| Scenario | Action |
|----------|--------|
| No flag | Ask `--saas` or `--local` |
| `_package-request.json` missing | Stop |
| `projects` empty | Stop |
| `environment` missing | Stop |
| env not in env-config.json | Stop with actual value |
| No changes since baseline | Stop with `no-changes` |
| Excel COM error | Warn; continue (markdown guides OK) |

## Related

- Claude Code equivalent: `/kraken:create-saas-deployment-package --saas`
- Phase prompts: `references/workflow-phases.md`
- Component guide template: `templates/deployment-guide-template.md`
