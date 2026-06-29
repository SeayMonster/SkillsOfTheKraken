# Workflow phases — kraken-cursor-client-onboarding

Parent agent: execute phases in order. Launch parallel Task subagents in a **single message** when marked PARALLEL.

Inputs locked after Phase 1: `repoRoot`, `clientName`, `portalFileName`, `projects[]`, `environmentExcel`.

---

## Phase 1: Coordinate

**Parent executes** Steps 1–3 (requires user input for project tags).

Return structured state for Phase 2–3 agents.

If `needsSetupCopilot`: invoke **kraken-cursor-setup-copilot** before or after Wire phase.

---

## Phase 2: Generate (PARALLEL — 5 Tasks in one message)

### 2a client.json
Write `client.json` per SKILL.md Step 4.

### 2b README.md
Write `README.md` per Step 5.

### 2c Setup.ps1
Write idempotent `Setup.ps1` per Step 6.

### 2d Portal HTML
Write `{portalFileName}` per Step 7 (full portal spec in SKILL.md).

### 2e ONBOARDING.md
Write `ONBOARDING.md` per Step 8.

---

## Phase 3: Wire (PARALLEL — up to 5 Tasks)

- Append `.github/copilot-instructions.md` (Step 9)
- Append `CLAUDE.md` (Step 10)
- Update `.gitignore` (Step 11)
- Patch `CopyWebUI.bat` files for web projects (Step 12)
- Add `_Portal` solution folder to `.sln` (Step 13)

Each Task owns disjoint files — safe to parallelize.

---

## Phase 4: Finalize

**Parent executes:**
- Remind user to commit (Step 14 — only if user requested commit)
- Run **kraken-cursor-switch-database** or `Switch-SqlEnv.ps1 Dev`
- Restart Cursor; verify MCP

List all artifacts created.
