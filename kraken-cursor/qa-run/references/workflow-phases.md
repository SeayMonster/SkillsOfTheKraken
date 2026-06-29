# Workflow phases — kraken-cursor-qa-run

Parent agent: execute phases in order. Launch parallel Task subagents in a **single message** when marked PARALLEL (max 4 projects per batch).

Task settings: `subagent_type: generalPurpose`, pass the full prompt below as `prompt`.

State: rewrite `QA_BOTS_REPO\clients\<name>\.qa-run\results.json` after each project update (full file, not patch).

---

## Phase 1: Coordinate

**Parent executes** (or single Task if delegating).

```
You are the Coordinate agent for kraken-cursor-qa-run.

Client repo root: {clientRepoRoot}

Steps:
1. Read ~/.cursor/.kraken-cursor/qa-bots-path for QA_BOTS_REPO. If missing, stop.

2. Client name from Split-Path -Leaf (Get-Location).

3. Read qa-config.json from .cursor or .claude under clients/<name>/.

4. Parse .sln → .csproj list. Mark test projects skipped.

5. Detect checks per project (qa-dapper, qa-web-smoke, qa-openaccess, qa-oa-deployment, Snowflake manual-review).

6. Write initial results.json with all projects.

7. Launch qa-watcher.ps1 and report.html.

Return: clientName, qaBotsRepo, resultsPath, configPath, pendingProjects[].
```

---

## Phase 2: Execute (PARALLEL — one Task per project, batch up to 4)

Launch all Tasks in one message per batch.

```
You are the QA agent for project "{projectName}".

Project path: {projectPath}
Checks: {checksJson}
Results file: {resultsPath}
Config: {configPath}

Steps:
1. Set project status "running" in results.json (rewrite full file).

2. Run checks using leaf skills:
   - qa-dapper → kraken-cursor-qa-dapper
   - qa-web-smoke → kraken-cursor-qa-web-smoke (staging_url from config)
   - qa-openaccess → kraken-cursor-qa-openaccess
   - qa-oa-deployment → CopyWebUI.bat DLL audit (see qa-run SKILL.md)

3. Resolve status: error → fail; else pass (or manual-review/skipped per rules).

4. Write final status + issues for this project to results.json.

Return: { name, status, issues }.
```

Repeat for each project in `pendingProjects`. Process in batches of 4 if more than 4 projects.

---

## Phase 3: Finalize

**Parent executes.**

```
Set completed_at in results.json. Print pass/fail/manual/skipped summary and dashboard path.
```
