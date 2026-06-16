---
description: QA test for OpenAccess ASCX controls. Discovers controls in the current project, queries ix_web_page in the configured CKB DB to find parent pages, then uses Playwright to login and navigate to each page asserting no errors.
---

You are running OpenAccess (OA) QA tests for this project.

## Context

OpenAccess is an IKnowledgeBase-based web application running locally at `https://<COMPUTERNAME>/ikb`.
ASCX controls inherit `UserControlBase`. They are hosted inside OA pages defined in `ix_web_page`.
The `Template` XML column maps controls to pages: `<ControlTemplate ControlType="ascx" Name="<ClassName>" ...>`.
Login: explicit username/password — `ckbadmin` / `ckbadmin`. Do NOT use Windows auth.

## Step 1: Probe OA Availability

Get the hostname:
```powershell
$env:COMPUTERNAME
```

Use Playwright MCP to navigate to `https://<COMPUTERNAME>/ikb`.

- If navigation succeeds (any response — including login redirect): continue to Step 2.
- If navigation fails (connection refused, timeout, DNS error): return immediately:
  ```json
  { "status": "skip", "issues": [{ "severity": "info", "message": "OA runtime not reachable at https://<COMPUTERNAME>/ikb — Playwright checks skipped." }] }
  ```

## Step 2: Resolve DB Connection

Check for the OA DB config file at `~/.claude/.qa-db.json`:

```powershell
$configPath = "$env:USERPROFILE\.claude\.qa-db.json"
if (Test-Path $configPath) {
    Get-Content $configPath | ConvertFrom-Json
}
```

**If the file exists and has `server` and `database` values:** use them. Skip to Step 2.

**If the file is missing or empty:**
1. Get hostname automatically:
   ```powershell
   $env:COMPUTERNAME
   ```
2. Ask: "Instance name? (press Enter for default instance, or type e.g. `v2022` or `SQLEXPRESS`)"
3. Ask: "Database name? (e.g. `CKB`)"
4. Build server string: default instance → `<COMPUTERNAME>`, named instance → `<COMPUTERNAME>\<instance>`
5. Save to `~/.claude/.qa-db.json`:
   ```powershell
   $config = @{ server = "<server>"; database = "<database>" }
   $config | ConvertTo-Json | Set-Content "$env:USERPROFILE\.claude\.qa-db.json" -Encoding utf8
   ```
6. Continue — no restart needed.

## Step 3: Discover ASCX Controls

Get the project path from the argument passed to this skill (the absolute path to the project directory).

Find all `.ascx` files in the project directory and subdirectories. For each, extract the filename without extension. These are the control names (matching the `Name` attribute in OA's Template XML).

If no `.ascx` files found: return `{ "status": "skip", "issues": [{ "severity": "info", "message": "No .ascx files found in project" }] }`. Stop.

## Step 4: Query ix_web_page for Each Control

For each control name, run via sqlcmd using the server and database from `.qa-db.json`:

```powershell
$server   = $dbConfig.server
$database = $dbConfig.database
$name     = "<ControlClassName>"

sqlcmd -S $server -E -d $database -h -1 -W -Q @"
SELECT TOP 1 Name, NavigateTo
FROM ix_web_page
WHERE CAST(Template AS NVARCHAR(MAX)) LIKE '%Name=""$name""%'
  AND IsNavigable = 1
ORDER BY DBKey
"@
```

Parse the output line: first token = page Name, second token = NavigateTo.
Collect as: `{ controlName, pageName, navigateTo }`. No rows returned → flag as `unfound`.

## Step 5: Build Test URLs

```powershell
$hostname = $env:COMPUTERNAME
```

For each control with a `navigateTo` value, build:
- Page URL: `https://<hostname>/ikb/<navigateTo>`

Login URL: `https://<hostname>/ikb`

## Step 6: Playwright Login

Use Playwright MCP to open a browser:

1. Navigate to `https://<hostname>/ikb`
2. Wait for the page to load. Locate username and password fields.
3. Fill username: `ckbadmin`
4. Fill password: `ckbadmin`
5. Click the login/submit button. Wait for navigation.
6. Confirm login succeeded — page should not show the login form anymore.

If login fails: return issue `{ "severity": "error", "message": "OA login failed for ckbadmin — verify OA is running at https://<hostname>/ikb" }`.

## Step 7: Navigate to Each Control Page

For each control that has a page URL:

1. Navigate to `https://<hostname>/ikb/<navigateTo>`
2. Wait for page load (network idle or 5 seconds)
3. Check for errors:
   - HTTP 4xx/5xx → error: `"Page <pageName> returned HTTP <status>"`
   - Browser console errors → warning: `"Console error on <pageName>: <message>"`
   - ASP.NET yellow screen / "Server Error" text → error: `"ASP.NET error on page <pageName>"`
   - Page contains "Object reference" or "Exception" → warning: `"Possible unhandled exception on <pageName>"`
4. Screenshot → `QA_BOTS_REPO\clients\<clientName>\.qa-run\screenshots\<controlName>.png`
   - QA_BOTS_REPO from `~/.claude/.qa-bots-path`
   - clientName = `Split-Path -Leaf (Get-Location)` from client repo

For controls with no page found (unfound): add issue `{ "severity": "warning", "message": "Control <controlName>.ascx has no navigable parent page in ix_web_page — likely a popup or context panel" }`.

## Step 8: Return Results

```json
{
  "status": "pass",
  "issues": []
}
```

Status:
- `pass` — no error-severity issues
- `fail` — any error-severity issue
- `skip` — OA runtime not reachable, or no .ascx files found
