---
name: kraken-cursor-sync-skills
description: >-
  Audits skills/ (Claude kraken) vs kraken-cursor/ (Cursor), translates missing
  skills, updates stale Cursor copies via parallel Task subagents, runs install.ps1,
  and reminds to refresh Claude plugin. Use when syncing kraken skills, translating
  Claude to Cursor, keeping kraken-cursor in sync, or after editing skills/ folder.
---

# kraken-cursor: sync-skills

**Announce at start:** "I'm using kraken-cursor-sync-skills to audit and sync Claude and Cursor kraken skills."

Keeps **two trees in one repo** aligned:

| Tree | Path | Runtime |
|------|------|-----------|
| Claude | `skills/<name>/` | `/plugin update kraken@SkillsOfTheKraken` |
| Cursor | `kraken-cursor/<name>/` | `kraken-cursor/install.ps1` → `~/.cursor/skills/` |

There is **no automatic sync** — this skill runs the audit and agent-driven translation.

## Invoke

- "sync kraken cursor skills"
- "translate all claude skills to cursor"
- "keep kraken skills in sync"
- "I updated skills/ — update kraken-cursor"

**Flags (optional):**
- `--audit-only` — report gaps, do not translate
- `--translate-all` — force re-check every skill (translate missing + update stale)
- `--install-only` — run `install.ps1` only

Default: audit → translate missing → update stale → install → remind Claude update.

## Pre-flight

1. Set `{repoRoot}` = SkillsOfTheKraken repo root (must contain `skills/` and `kraken-cursor/`).
2. Set `{SKILL_DIR}` = this skill folder (`kraken-cursor/sync-skills/` or installed copy).
3. Read `{repoRoot}/kraken-cursor/TRANSLATION.md`.
4. Read `{SKILL_DIR}/references/sync-phases.md` for phase prompts.

## Orchestration

| Phase | Agent | Parallelism |
|-------|-------|-------------|
| 1 Audit | Parent + Shell | single |
| 2 Translate missing | Task × N | up to 4 per message |
| 3 Update stale | Task × N | up to 4 per message |
| 4 Install | Parent + Shell | single |
| 5 Claude reminder | Parent | single |
| 6 Report | Parent | single |

Skip phases 2–3 if audit shows nothing to do (unless `--translate-all`).

## Phase 1 — Audit

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "{SKILL_DIR}/scripts/audit-sync.ps1" -RepoRoot "{repoRoot}"
```

Show user: missing count, stale count, extra-in-cursor count.

## Phases 2–3 — Agent translation

Use prompts; prompts in `references/sync-phases.md`. Each Task gets **one skill name** and **exclusive target folder**.

**Do not** edit `skills/` (Claude source) during sync — only `kraken-cursor/`.

## Phase 4 — Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "{repoRoot}/kraken-cursor/install.ps1"
```

User should restart Cursor or start a new Agent chat after install.

## Shared assets rule

When syncing, copy these from source to target if source is newer:

- `scripts/*`, `references/*`, `templates/*`, `*.ps1`, `*.html`, `*.py`, `*.js`

Do **not** overwrite Cursor-only files:

- `references/workflow-phases.md` (Task orchestration — merge manually if source workflow.js changed)

If `skills/<name>/workflow.js` changed, spawn a dedicated Task to update `kraken-cursor/<name>/references/workflow-phases.md`.

## Workflow.js skills

| Skill | Claude | Cursor |
|-------|--------|--------|
| create-saas-deployment-package | workflow.js | workflow-phases.md |
| create-reporting-deploy-package | workflow.js | workflow-phases.md |

When `workflow.js` mtime is newer than `workflow-phases.md`, include in stale update with explicit workflow port instructions.

## After you edit skills/ manually

Run this skill (or `--audit-only` first). Do not edit `kraken-cursor/` and `skills/` independently without syncing.

## Related

- Conventions: `{repoRoot}/kraken-cursor/TRANSLATION.md`
- Claude update: `/plugin update kraken@SkillsOfTheKraken`
