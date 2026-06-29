---
name: kraken-cursor-qa-openaccess-playwright
description: >-
  Runtime QA for OpenAccess ASCX controls. Discovers controls in the current
  project, queries ix_web_page in the configured CKB DB to find parent pages,
  then uses Playwright to login and navigate to each page asserting no errors.
  Use when the user asks for OpenAccess Playwright QA, kraken-cursor-qa-openaccess-playwright,
  OA runtime tests, or ASCX page-load validation.
argument-hint: [project-directory-path]
---

# kraken-cursor: qa-openaccess-playwright

**Announce at start:** "I'm using kraken-cursor-qa-openaccess-playwright to run OpenAccess runtime tests."

OpenAccess is an IKnowledgeBase-based web application running locally at `https://<COMPUTERNAME>/ikb`.
ASCX controls inherit `UserControlBase`. They are hosted inside OA pages defined in `ix_web_page`.
The `Template` XML column maps controls to pages: `<ControlTemplate ControlType="ascx" Name="<ClassName>" ...>`.
Login: explicit username/password — `ckbadmin` / `ckbadmin`. Do NOT use Windows auth.

Project directory: `$0` (argument) or current working directory if not provided.

## Step 1 — Probe OA availability

Get the hostname via Shell:

```powershell
$env:COMPUTERNAME
```

Use **plugin-playwright-playwright** MCP (preferred) or **cursor-ide-browser** MCP to navigate to `https://<COMPUTERNAME>/ikb`. Read tool schemas under the MCP descriptors before calling.

- If navigation succeeds (any response — including login redirect): continue to Step 2.
- If navigation fails (connection refused, timeout, DNS error): return immediately:

```json
{ "status": "skip", "issues": [{ "severity": "info", "message": "OA runtime not reachable at https://<COMPUTERNAME>/ikb — Playwright checks skipped." }] }
```

## Step 2 — Resolve DB connection

Check for the OA DB config file at `~/.cursor/.kraken-cursor/qa-db.json`:

```powershell
$configPath = Join-Path $env:USERPROFILE ".cursor\.kraken-cursor\qa-db.json"
if (Test-Path $configPath) {
    Get-Content $configPath | ConvertFrom-Json
}
```

**If the file exists and has `server` and `database` values:** use them. Continue to Step 3.

**If the file is missing or empty:**

1. Get hostname automatically: `$env:COMPUTERNAME`
2. Ask: "Instance name? (press Enter for default instance, or type e.g. `v2022` or `SQLEXPRESS`)"
3. Ask: "Database name? (e.g. `CKB`)"
4. Build server string: default instance → `<COMPUTERNAME>`, named instance → `<COMPUTERNAME>\<instance>`
5. Save to `~/.cursor/.kraken-cursor/qa-db.json`:

```powershell
$configDir = Join-Path $env:USERPROFILE ".cursor\.kraken-cursor"
New-Item -ItemType Directory -Force $configDir | Out-Null
$config = @{ server = "<server>"; database = "<database>" }
$config | ConvertTo-Json | Set-Content (Join-Path $configDir "qa-db.json") -Encoding utf8
```

6. Continue — no restart needed.

## Step 3 — Discover ASCX controls

Glob all `.ascx` files under `$0` (recursive). For each, extract the filename without extension. These are the control names (matching the `Name` attribute in OA's Template XML).

If no `.ascx` files found: return `{ "status": "skip", "issues": [{ "severity": "info", "message": "No .ascx files found in project" }] }`. Stop.

## Step 4 — Query ix_web_page for each control

For each control name, run via sqlcmd using the server and database from `~/.cursor/.kraken-cursor/qa-db.json`:

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

## Step 5 — Build test URLs

```powershell
$hostname = $env:COMPUTERNAME
```

For each control with a `navigateTo` value, build:

- Page URL: `https://<hostname>/ikb/<navigateTo>`
- Login URL: `https://<hostname>/ikb`

## Step 6 — Playwright login

Use **plugin-playwright-playwright** MCP. Read tool schemas before calling.

1. `browser_navigate` to `https://<hostname>/ikb`
2. Wait for the page to load. Locate username and password fields via `browser_snapshot`.
3. `browser_fill` username: `ckbadmin`
4. `browser_fill` password: `ckbadmin`
5. Click the login/submit button. Wait for navigation.
6. Confirm login succeeded — page should not show the login form anymore.

If login fails: return issue `{ "severity": "error", "message": "OA login failed for ckbadmin — verify OA is running at https://<hostname>/ikb" }`.

If **plugin-playwright-playwright** is unavailable, fall back to **cursor-ide-browser** MCP (`browser_navigate`, `browser_fill`, `browser_click`, `browser_snapshot`).

## Step 7 — Navigate to each control page

For each control that has a page URL:

1. Navigate to `https://<hostname>/ikb/<navigateTo>`
2. Wait for page load (network idle or 5 seconds)
3. Check for errors:
   - HTTP 4xx/5xx → error: `"Page <pageName> returned HTTP <status>"`
   - Browser console errors → warning: `"Console error on <pageName>: <message>"` (via `browser_console_messages` or `browser_cdp`)
   - ASP.NET yellow screen / "Server Error" text → error: `"ASP.NET error on page <pageName>"`
   - Page contains "Object reference" or "Exception" → warning: `"Possible unhandled exception on <pageName>"`
4. Screenshot → `QA_BOTS_REPO\clients\<clientName>\.qa-run\screenshots\<controlName>.png`
   - `QA_BOTS_REPO` from `~/.cursor/.kraken-cursor/qa-bots-path` (read the single-line path file; ask user if missing — see kraken-cursor-qa-init)
   - `clientName` = `Split-Path -Leaf (Get-Location)` from client repo

For controls with no page found (unfound): add issue `{ "severity": "warning", "message": "Control <controlName>.ascx has no navigable parent page in ix_web_page — likely a popup or context panel" }`.

## Step 8 — Return results

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

## Error handling

- Playwright MCP unavailable: issue `{ "severity": "error", "message": "Playwright MCP unavailable. Enable plugin-playwright-playwright or use cursor-ide-browser for web-ui cases." }` and stop browser steps.
- sqlcmd not found on PATH: issue `{ "severity": "error", "message": "sqlcmd not found. Install SQL Server command-line tools." }` and skip DB lookup steps.
