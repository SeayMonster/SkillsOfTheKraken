---
description: Run QA checks on the current client repository. Parses the .sln to find all projects, auto-detects applicable checks (qa-dapper, qa-web-smoke), writes results.json, launches terminal watcher and browser dashboard. Orchestrates parallel per-project agents via workflow.js. Run from the client repo in Claude Code.
---

**Announce at start:** "I'm using qa-run to run QA analysis on this client repository."

You are running QA analysis on this client repository. **Prefer the multi-agent workflow** for Step 5 execution (parallel per-project agents).

## Prerequisites Check

1. Read `~/.claude/.qa-bots-path` to get QA_BOTS_REPO.
   - If file does not exist: "Run crisp-tc:qa-init first to set up this client's workspace." Stop.

2. Determine client name: run `Split-Path -Leaf (Get-Location)` in PowerShell.

3. Check client config exists: `QA_BOTS_REPO\clients\<name>\.claude\qa-config.json`
   - If not found: "No workspace found for <name>. Run crisp-tc:qa-init first." Stop.

4. Read `solution_path` from qa-config.json.

## Step 1: Parse Solution File

Read the `.sln` file at solution_path. Extract all `.csproj` project paths using this pattern:
```
Project("{...}") = "ProjectName", "relative\path\to\Project.csproj", "{GUID}"
```
Collect each relative path, resolve it against the solution directory to get the full absolute path to each `.csproj` file. Exclude projects whose name contains `.Tests` or `Test` — mark them as `skipped`.

## Step 2: Detect Checks Per Project

For each non-test project, scan its `.cs` files to detect which checks apply:

**qa-dapper:** grep for any of: `using Dapper`, `SqlMapper`, `QueryAsync`, `ExecuteAsync`, `QueryFirstOrDefault`, `IDbConnection`
- If found: add `qa-dapper` to this project's checks

**qa-web-smoke:** grep for any of: `[ApiController]`, `[Route(`, `ControllerBase`, `WebApplication`, `app.MapGet`, `app.MapPost`
- If found: add `qa-web-smoke` to this project's checks
- If qa-web-smoke needed: check `staging_url` in qa-config.json
  - If missing: ask "Enter the staging URL for <project-name> (e.g. https://staging.example.com):"
  - Save `staging_url` back to qa-config.json for future runs

**qa-openaccess:** grep for any of: `UserControlBase`, `ICommandManager`, `IPopupControlSubscriber` in `.cs` files, OR find any `.ascx` files in the project directory
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

Run this PowerShell (replace QA_BOTS_REPO and <name> with actual values):

```powershell
Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-File", "QA_BOTS_REPO\_shared\qa-watcher.ps1",
    "-QaBotsRepo", "QA_BOTS_REPO",
    "-ClientName", "<name>"
)
Start-Process "QA_BOTS_REPO\clients\<name>\.qa-run\report.html"
```

## Step 5–6: Execute Checks + Finalize (multi-agent workflow)

After Steps 1–4, invoke the Workflow (parallel one agent per pending project, batches of 4):

```
Workflow({
  scriptPath: "{SKILL_DIR}/workflow.js",
  args: { clientRepoRoot: "<absolute path to current client repo>" }
})
```

Resolve `{SKILL_DIR}` to the directory containing this skill's `SKILL.md` (plugin cache or repo `skills/qa-run/`).

### Per-project check rules (each Execute agent)

- **qa-dapper:** Invoke crisp-tc:qa-dapper on each `.cs` file. Issues: `{ "severity": "error"|"warning", "message": "..." }`.
- **qa-web-smoke:** Invoke crisp-tc:qa-web-smoke with staging URL from qa-config.json.
- **qa-openaccess:** Invoke crisp-tc:qa-openaccess with project directory path.
- **qa-oa-deployment:** Audit `.csproj` HintPath DLLs vs `CopyWebUI.bat` copy lines (+ packages.config version warnings).
- **manual-review (Snowflake):** Skip automated checks; info issue only.
- **skipped:** Issues = `[]`.

Status: any error → `fail`; warnings/info only or none → `pass`; manual-review → `manual-review`.

The Finalize phase sets `completed_at` and prints the summary dashboard path.
