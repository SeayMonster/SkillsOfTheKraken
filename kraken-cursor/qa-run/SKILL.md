---
name: kraken-cursor-qa-run
description: >-
  Runs QA analysis on the current client repository. Parses the .sln to find all
  projects, auto-detects applicable checks (Dapper, web smoke, Open Access),
  writes results.json, and launches the terminal watcher and browser dashboard.
  Use when the user asks to run QA, kraken-cursor-qa-run, full QA analysis,
  or QA checks from a client repo in Cursor.
---

# kraken-cursor: qa-run

**Announce at start:** "I'm using kraken-cursor-qa-run to run QA analysis on this client repository."

Runs QA analysis on the current client repository.

## Pre-flight

1. Read `~/.cursor/.kraken-cursor/qa-bots-path` to get `QA_BOTS_REPO`.
   - If the file does not exist: "Run kraken-cursor-qa-init first to set up this client's workspace." Stop.

2. Determine client name: run `Split-Path -Leaf (Get-Location)` in PowerShell.

3. Check client config exists at `QA_BOTS_REPO\clients\<name>\.cursor\qa-config.json` or `QA_BOTS_REPO\clients\<name>\.claude\qa-config.json`.
   - If not found: "No workspace found for <name>. Run kraken-cursor-qa-init first." Stop.

4. Read `solution_path` from the config file found above.

## Step 1: Parse Solution File

Read the `.sln` file at `solution_path`. Extract all `.csproj` project paths using this pattern:

```
Project("{...}") = "ProjectName", "relative\path\to\Project.csproj", "{GUID}"
```

Collect each relative path, resolve it against the solution directory to get the full absolute path to each `.csproj` file. Exclude projects whose name contains `.Tests` or `Test` — mark them as `skipped`.

## Step 2: Detect Checks Per Project

For each non-test project, scan its `.cs` files to detect which checks apply:

**kraken-cursor-qa-dapper:** grep for any of: `using Dapper`, `SqlMapper`, `QueryAsync`, `ExecuteAsync`, `QueryFirstOrDefault`, `IDbConnection`
- If found: add `qa-dapper` to this project's checks

**kraken-cursor-qa-web-smoke:** grep for any of: `[ApiController]`, `[Route(`, `ControllerBase`, `WebApplication`, `app.MapGet`, `app.MapPost`
- If found: add `qa-web-smoke` to this project's checks
- If qa-web-smoke needed: check `staging_url` in qa-config.json
  - If missing: ask "Enter the staging URL for <project-name> (e.g. https://staging.example.com):"
  - Save `staging_url` back to qa-config.json for future runs

**kraken-cursor-qa-openaccess:** grep for any of: `UserControlBase`, `ICommandManager`, `IPopupControlSubscriber` in `.cs` files, OR find any `.ascx` files in the project directory
- If found: add `qa-openaccess` to this project's checks

**qa-oa-deployment:** triggered when `qa-openaccess` is detected AND a `CopyWebUI.bat` exists in the project directory
- If found: add `qa-oa-deployment` to this project's checks

**Snowflake:** grep for any of: `Snowflake.Data`, `SnowflakeDbConnection`, `snowflake.net`
- If found: mark project as `manual-review`. Do NOT add other checks.

## Step 3: Initialize results.json

Write this file to `QA_BOTS_REPO\clients\<name>\.qa-run\results.json`:

```json
{
  "client": "<name>",
  "solution": "<solution_path>",
  "started_at": "<current ISO 8601 timestamp>",
  "completed_at": null,
  "projects": [
    {
      "name": "<ProjectName>",
      "path": "<absolute-path-to-csproj-directory>",
      "checks": ["qa-dapper"],
      "status": "pending",
      "issues": []
    }
  ]
}
```

Include ALL projects (including skipped and manual-review) in the array with their detected status.

## Step 4: Launch Watcher and Dashboard

Run this PowerShell (replace `QA_BOTS_REPO` and `<name>` with actual values):

```powershell
Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-File", "QA_BOTS_REPO\_shared\qa-watcher.ps1",
    "-QaBotsRepo", "QA_BOTS_REPO",
    "-ClientName", "<name>"
)
Start-Process "QA_BOTS_REPO\clients\<name>\.qa-run\report.html"
```

## Step 5–6: Execute + Finalize (multi-agent)

Read `{SKILL_DIR}/references/workflow-phases.md` and run phases in order:

1. **Coordinate** — parent runs Steps 1–4 above (pre-flight through dashboard).
2. **Execute (PARALLEL)** — launch up to **4 Task subagents per message**, one per pending project. Each Task runs leaf skills (`kraken-cursor-qa-dapper`, `kraken-cursor-qa-web-smoke`, `kraken-cursor-qa-openaccess`, qa-oa-deployment audit) and updates `results.json`.
3. **Finalize** — parent sets `completed_at` and prints summary.

### Per-project check rules

- **qa-dapper:** kraken-cursor-qa-dapper on each `.cs` file.
- **qa-web-smoke:** kraken-cursor-qa-web-smoke with staging URL.
- **qa-openaccess:** kraken-cursor-qa-openaccess with project path.
- **qa-oa-deployment:** CopyWebUI.bat DLL audit (HintPath vs copy lines, packages.config versions).
- **manual-review / skipped:** per SKILL.md Step 2 rules.

Status: error → `fail`; warnings/info only → `pass`.
