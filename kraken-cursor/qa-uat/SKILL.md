---
name: kraken-cursor-qa-uat
description: >-
  Runs UAT validation for the current client repository. Reads test cases from
  Google Doc or local fallback, maps to solution projects via config, executes
  web-ui (Playwright) and db-assert (sqlcmd) checks. Use when the user asks for
  UAT validation, kraken-cursor-qa-uat, user acceptance testing, or Playwright
  and sqlcmd UAT runs from a client repo in Cursor.
---

# kraken-cursor: qa-uat

**Announce at start:** "I'm using kraken-cursor-qa-uat to run UAT validation."

Runs UAT validation for the current client repository.

## Pre-flight

1. Read `~/.cursor/.kraken-cursor/qa-bots-path` to get `QA_BOTS_REPO`.
   - If the file does not exist: "Run kraken-cursor-qa-init first to set up this client's workspace." Stop.

2. Determine client name: run `Split-Path -Leaf (Get-Location)` in PowerShell.

3. Check `QA_BOTS_REPO\clients\<name>\.cursor\qa-config.json` or `QA_BOTS_REPO\clients\<name>\.claude\qa-config.json` exists.
   - If not: "No workspace found for <name>. Run kraken-cursor-qa-init first." Stop.

4. Read config. Required fields:
   - `uat_doc_id` — Google Doc ID. If missing: "Add uat_doc_id to qa-config.json." Stop.
   - `epic_project_map` — object mapping project names to epic IDs. If missing or empty: "Add epic_project_map to qa-config.json." Stop.
   - `uat_base_url` — base URL for web-ui tests. If missing and any web-ui cases exist: prompt once, save back to config.
   - `uat_db_server`, `uat_db_name` — sqlcmd target. Defaults: `cx-lpt676\v2022`, `ckb`.

## Step 1: Fetch UAT Test Cases

**Try Google Drive MCP first:**
Use any available Google Drive read tool to fetch the file by ID (`uat_doc_id`). Inspect MCP tool descriptors under the project's `mcps/` folder before calling.

**If MCP unavailable or throws any error:**
Prompt: "Google Drive unavailable. Enter path to UAT doc (txt/md/docx):"
Read the file at the provided path using the Read tool.

**Parse the content into test cases.** The document structure is:
- Section headers: `# Epic N: <Epic Name>` (e.g., `# Epic 4: Open Access Planogram Version/Copy`)
- Tables with columns: `Test Case ID | User Story | Action / Test Step | Expected System Result | Pass / Fail`

Extract each table row into:

```
{
  id:              "PVC-01",
  epic:            "Epic 4",
  epic_name:       "Open Access Planogram Version/Copy",
  action_steps:    "<full text of Action / Test Step column>",
  expected_result: "<full text of Expected System Result column>"
}
```

Ignore the Pass / Fail column. Ignore prerequisite setup sections and non-table text.

## Step 2: Filter by epic_project_map

For each test case:
- Look up `epic` in `epic_project_map` (match key like `"POGSplit": ["Epic 4"]` — find the project whose value array contains this epic ID).
- If found: assign `project = <project-name>`.
- If not found: assign `status = "not-done"`, `reason = "no-project-mapping"`, skip classification.

## Step 3: Classify Mapped Test Cases

Scan `action_steps` (lowercase comparison) for keyword sets:

**web-ui keywords:** `log into open access`, `navigate to`, `web publisher`, `open access`, `click`, `browser`, `log in`, `log into`

**db-assert keywords:** `query the`, `verify the database`, `check ckb`, `ckb database`, `query`, `information_schema`, `database record`, `database table`

**not-done keywords:** `sftp`, `postman`, `api payload`, `space planning`, `floor planning`, `citrix`, `thick client`, `email`

**Classification logic (apply in order):**
1. Contains any not-done keyword → `classification: "not-done"`, `reason: "no-local-runner"`
2. Contains both web-ui and db-assert keywords → `classification: "mixed"`
3. Contains only web-ui keywords → `classification: "web-ui"`
4. Contains only db-assert keywords → `classification: "db-assert"`
5. No match → `classification: "not-done"`, `reason: "no-local-runner"`

## Step 4: Initialize uat-results.json

Write to `QA_BOTS_REPO\clients\<name>\.qa-run\uat-results.json`:

```json
{
  "client":       "<name>",
  "doc_id":       "<uat_doc_id>",
  "doc_source":   "google-drive",
  "started_at":   "<current ISO 8601 timestamp>",
  "completed_at": null,
  "test_cases": [
    {
      "id":             "<test case id>",
      "epic":           "<epic id>",
      "project":        "<project name or null>",
      "classification": "<web-ui|db-assert|mixed|not-done>",
      "reason":         "<no-project-mapping|no-local-runner or omit if not not-done>",
      "status":         "<pending or not-done>",
      "issues":         []
    }
  ]
}
```

Set `doc_source` to `"disk"` if the fallback path was used. Set initial `status` to `"not-done"` for not-done cases, `"pending"` for all others.

## Step 5: Launch Watcher and Dashboard

```powershell
Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-File", "QA_BOTS_REPO\_shared\qa-watcher.ps1",
    "-QaBotsRepo", "QA_BOTS_REPO",
    "-ClientName", "<name>"
)
Start-Process "QA_BOTS_REPO\clients\<name>\.qa-run\report.html"
```

## Step 6: Execute Test Cases

For each test case where `status = "pending"`:

1. Update `status` to `"running"` in `uat-results.json` (write the full file).

### web-ui runner (Playwright MCP)

Use the **plugin-playwright-playwright** MCP server for browser automation. Read tool schemas under the MCP descriptors before calling.

1. Navigate to `uat_base_url` using the Playwright MCP navigate/open tool.
2. Follow the `action_steps` as navigation instructions. Use Playwright MCP tools for:
   - URL navigation
   - Locating elements (click, fill, select)
   - Reading page text and snapshots for assertions
3. Assert the `expected_result` against page content.
4. Check console messages and network responses for JS errors and HTTP 4xx/5xx (via Playwright MCP or `browser_cdp` on **cursor-ide-browser** if Playwright lacks console/network access).

Collect issues:
- Console errors or HTTP 4xx/5xx → `{ "severity": "error", "message": "Console error: <msg>" }`
- Expected content not found → `{ "severity": "warning", "message": "Expected '<text>' not found on page" }`

### db-assert runner (sqlcmd)

Derive SQL assertions from `expected_result` and the project's stored procedures/schema.

**POGSplit (Epic 4) assertion template** — run after a split operation:

```sql
-- Job completed
SELECT Status FROM ckbcustom.cx_job WHERE DBKey = @jobKey
-- expect: 'Completed'

-- New live copy exists with correct name and original status
SELECT COUNT(*) FROM ix_spc_planogram WHERE name = @newName AND dbstatus = @srcStatus
-- expect: 1

-- WIP version created with "Version of" prefix (dbstatus = 3)
SELECT COUNT(*) FROM ix_spc_planogram WHERE name = 'Version of ' + @newName AND dbstatus = 3
-- expect: 1

-- Source planogram unchanged
SELECT name, dbstatus FROM ix_spc_planogram WHERE dbkey = @origKey
-- expect: name and dbstatus match pre-run snapshot

-- Stores reassigned
SELECT COUNT(*) FROM ix_flr_performance WHERE DBParentPlanogramKey = @newPogKey
-- expect: equals number of stores moved to new planogram
```

For other epics: derive assertions from `expected_result` text, using `INFORMATION_SCHEMA.COLUMNS` to confirm column names before writing queries.

Execute each query:

```powershell
sqlcmd -S <uat_db_server> -d <uat_db_name> -E -Q "<query>" -h -1 -W
```

Parse output. Any unexpected value → `{ "severity": "error", "message": "Expected <X>, got <Y>" }`.

### mixed runner

Run web-ui runner, then db-assert runner. Concatenate all issues from both.

### Status resolution

After all runners complete for a test case:
- Any issue with `severity: "error"` → `status = "fail"`
- Issues only `severity: "warning"` or no issues → `status = "pass"`
- Write updated `uat-results.json`.

## Step 7: Finalize

Set `completed_at` to current ISO 8601 timestamp in `uat-results.json`.

Print summary:

```
UAT Complete — <name>
─────────────────────────────────
Pass:     N test cases
Fail:     N test cases
Not Done: N test cases

Dashboard: QA_BOTS_REPO\clients\<name>\.qa-run\report.html
```

## Error Handling

- Google Drive MCP returns partial content (>95K chars): content is saved to a temp file — read it from disk using the Read tool with offsets.
- sqlcmd not found on PATH: issue `{ "severity": "error", "message": "sqlcmd not found. Install SQL Server command-line tools." }` and skip all db-assert cases.
- Playwright MCP unavailable: issue `{ "severity": "error", "message": "Playwright MCP unavailable. Enable plugin-playwright-playwright or use cursor-ide-browser for web-ui cases." }` and skip all web-ui cases.
