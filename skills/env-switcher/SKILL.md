---
name: env-switcher
description: >
  Generates a Switch-SqlEnv.ps1 script for a project that has an environment
  configuration Excel file (.xlsx). The script lets developers switch the
  mssql-server MCP connection between environments (Dev / Test / Prod or
  similar) with a single command. Use this skill whenever a user wants to
  set up environment switching, automate database connection swapping, generate
  a Switch-SqlEnv script, or asks how to point Claude at a different client
  database environment from an Excel config file.
---

# crisp-dev-env-switcher

## What this skill does

Inspects the project's environment config Excel file, figures out its structure,
and writes a `Switch-SqlEnv.ps1` PowerShell script that:

1. Parses the Excel on every run (no stale copies)
2. Writes `env-config.json` alongside the Excel (gitignored — contains credentials)
3. Reconfigures the `mssql-server` MCP entry for the chosen environment
4. Uses **Excel COM automation** if Excel is installed, falls back to the
   **ImportExcel** PowerShell module if not — and errors clearly if neither is available

---

## Step 1 — Find and inspect the Excel file

Look for a `.xlsx` file in the project that describes environment connection
details. Common locations: `Environment Details/`, `Config/`, repo root.

Read the file with openpyxl to understand its structure:

```python
import openpyxl
wb = openpyxl.load_workbook(path, data_only=True)
print(wb.sheetnames)          # → which sheets = which environments
ws = wb[wb.sheetnames[0]]
for row in ws.iter_rows(values_only=True):
    if any(c for c in row):
        print(row)
```

You're looking for:
- **Sheet names** — these become the environment choices (e.g. Dev, Test, Prod)
- **DatabaseServer** row — the SQL Server hostname
- **Database Name** row — the database name (may have trailing colon/space in key)
- **DB Super UserID** row — SQL login username
- **Password** row — SQL login password

If the key names differ from the above, note the actual names — you'll need them
in the generated script.

---

## Step 2 — Generate Switch-SqlEnv.ps1

Write the script to the **repo root** (same level as the solution file). Use
the actual Excel path, sheet names, and row key names you found in Step 1.

The script structure:

```powershell
# Switch-SqlEnv.ps1
# [brief description of what it does and how to use it]
#
# Requires Excel (COM) OR: Install-Module ImportExcel -Scope CurrentUser
#
# Usage:
#   .\Switch-SqlEnv.ps1 Dev
#   .\Switch-SqlEnv.ps1 Test
#   .\Switch-SqlEnv.ps1 Prod

param(
    [ValidateSet("<env1>","<env2>","<env3>")]   # use actual sheet names
    [string]$Environment
)

$xlPath   = Join-Path $PSScriptRoot "<relative path to Excel>"
$jsonPath = Join-Path $PSScriptRoot "<relative path to env-config.json>"

# 1. Validate Excel exists
# 2. Prompt for environment if not provided
# 3. Detect parser (COM > ImportExcel > error)
# 4. Parse all sheets → build $result hashtable
# 5. Write $result as JSON to $jsonPath
# 6. Read chosen environment from $result
# 7. Validate server is populated
# 8. Print summary (env / server / database / user)
# 9. claude mcp remove + claude mcp add
# 10. Remind user to restart Claude Code
```

### Parser detection block (always include this)

```powershell
$useCOM = $false
try {
    $null = New-Object -ComObject Excel.Application -ErrorAction Stop
    $useCOM = $true
    Write-Host "Using COM (Excel installed)"
} catch {
    if (Get-Module -ListAvailable -Name ImportExcel) {
        Write-Host "Using ImportExcel module"
    } else {
        Write-Error "No Excel parser available. Either install Excel or run: Install-Module ImportExcel -Scope CurrentUser"
        exit 1
    }
}
```

### COM parse helper

```powershell
function Parse-Sheet-COM($workbook, $sheetName) {
    $ws   = $workbook.Sheets.Item($sheetName)
    $data = @{}
    $row  = 1
    while ($ws.Cells.Item($row, 1).Text -ne "" -or $row -lt 50) {
        $key = $ws.Cells.Item($row, 1).Text
        $val = $ws.Cells.Item($row, 2).Text
        if ($key) {
            $data[$key.Trim().TrimEnd(':').Trim()] = if ($val) { $val.Trim() } else { $null }
        }
        $row++
    }
    return $data
}
```

Always release COM objects in a `finally` block:

```powershell
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
try {
    $wb = $excel.Workbooks.Open($xlPath)
    # ... parse sheets ...
} finally {
    $wb.Close($false)
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
}
```

### ImportExcel parse helper

```powershell
function Parse-Sheet-ImportExcel($xlPath, $sheetName) {
    $rows = Import-Excel -Path $xlPath -WorksheetName $sheetName -NoHeader
    $data = @{}
    foreach ($row in $rows) {
        $key = $row.P1
        if ($key) {
            $data[$key.ToString().Trim().TrimEnd(':').Trim()] = if ($row.P2) { $row.P2.ToString().Trim() } else { $null }
        }
    }
    return $data
}
```

### MCP swap block

```powershell
claude mcp remove mssql-server 2>$null
claude mcp add `
    --transport stdio `
    --env MSSQL_SERVER=$($cfg.Server) `
    --env MSSQL_DATABASE=$($cfg.Database) `
    --env MSSQL_USER=$($cfg.User) `
    --env MSSQL_PASSWORD=$($cfg.Password) `
    --env "MSSQL_DRIVER=ODBC Driver 17 for SQL Server" `
    mssql-server -- python -m mssql_mcp_server
```

---

## Step 3 — Update .gitignore

Add the `env-config.json` path to `.gitignore` if not already there. It
contains credentials and must never be committed.

```
# Environment config JSON — generated from Excel, contains credentials
<relative path to env-config.json>
```

---

## Step 4 — Commit and push

Stage and commit `Switch-SqlEnv.ps1` and the updated `.gitignore`. Do not
stage `env-config.json`.

---

## Step 5 — Tell the user how to use it

After committing, summarize:

- **First time after pulling the repo:** run `.\Switch-SqlEnv.ps1 Dev` — it
  generates the JSON and swaps the connection in one step
- **One-time module install** if no Excel: `Install-Module ImportExcel -Scope CurrentUser`
- **Restart Claude Code** after running the script for the new connection to load
