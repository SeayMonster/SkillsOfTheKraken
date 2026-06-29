# Sync phases — kraken-cursor-sync-skills

Parent agent: run phases in order. Use Task subagents for translation work (parallel when disjoint).

---

## Phase 1: Audit

Run from repo root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "{SKILL_DIR}/scripts/audit-sync.ps1"
```

Parse JSON output:
- `missingInCursor` — skills in `skills/` with no `kraken-cursor/<name>/`
- `staleInCursor` — Claude folder newer than Cursor counterpart (by file mtime)
- `extraInCursor` — Cursor-only skills (usually OK; report only)

If `missingInCursor` and `staleInCursor` are both empty, skip to **Phase 4** (install verify only).

Report summary to user before translating.

---

## Phase 2: Translate missing (PARALLEL — one Task per skill, batch up to 4 per message)

For each skill in `missingInCursor`, launch Task with:

```
You are translating one kraken skill to Cursor.

Repo: {repoRoot}
READ FIRST: {repoRoot}/kraken-cursor/TRANSLATION.md

Source: {repoRoot}/skills/{skillName}/
Target: {repoRoot}/kraken-cursor/{skillName}/  (create only this folder)

Rules:
- name: kraken-cursor-{skillName}
- Third-person description, flatten XML blocks
- Apply all replacements in TRANSLATION.md
- Copy scripts/, references/, templates/, *.ps1 from source unchanged unless Claude-specific
- For plugin-digest: omit CronCreate; use cursor-ide-browser
- For register-skill-repo / add-marketplace: Cursor install paths
- No Workflow(), no hardcoded C:\\Users\\ paths

Return: files created.
```

Batch skills into groups of 4 parallel Tasks per message.

---

## Phase 3: Update stale (PARALLEL — same as Phase 2 but merge)

For each skill in `staleInCursor`:

```
You are syncing an existing kraken-cursor skill with its Claude source.

Repo: {repoRoot}
READ: {repoRoot}/kraken-cursor/TRANSLATION.md
Source: {repoRoot}/skills/{skillName}/
Target: {repoRoot}/kraken-cursor/{skillName}/

Compare source vs target. Preserve Cursor-specific orchestration:
- Task subagent phases in references/workflow-phases.md
- kraken-cursor-* naming and MCP references

Update target so domain logic, scripts, and templates match source.
Do not reintroduce Workflow() or Claude-only APIs.

Return: list of files changed and what was merged.
```

If source removed a skill entirely, ask user before deleting Cursor folder.

---

## Phase 4: Install Cursor skills

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "{repoRoot}/kraken-cursor/install.ps1"
```

Verify installed count matches cursor skill folder count (excluding sync-skills from count if desired).

---

## Phase 5: Claude refresh reminder

Tell user (do not run automatically unless they asked):

```
In Claude Code:
  /plugin update kraken@SkillsOfTheKraken
  /reload-plugins
```

If they develop from local clone only, ensure changes are pushed to GitHub first so Claude marketplace picks them up.

---

## Phase 6: Report

```markdown
## kraken-cursor sync complete

- Translated: [list]
- Updated: [list]
- Already in sync: N skills
- Cursor installed: N skills → ~/.cursor/skills/
- Claude: run /plugin update if pushed to GitHub
```
