---
name: ba-uat-pull
description: Exports current Notion UAT test cases to a local Excel file. One sheet per Feature Area. Writes a _SyncMeta sheet so ba-uat-import can detect if Notion was edited after the BA started working. Always run this before editing your UAT Excel — never edit a stale copy.
trigger: Use this skill when a BA says "pull the UAT data", "export UAT to Excel", "get the latest test cases", "download the UAT", or "update my Excel from Notion".
---

# BA — Pull Notion UAT to Excel

<context>

## What this skill does

Exports the current Notion UAT database to a local Excel file so the BA can edit test cases in Excel. Writes a `_SyncMeta` sheet that records the sync timestamp and each row's Notion page ID. When the BA imports the file back, `ba-uat-import` reads the metadata and blocks any row where Notion was edited after this pull.

**Always pull before you edit. Never edit a copy you didn't just pull.**

---

</context>

<task>

## Step 1 — Load config

Read `docs/ba-config.json`.

- If `notion.uat_database_id` contains `REPLACE_WITH_`, STOP:
  > "The Notion UAT database hasn't been set up yet. Ask your dev to run `/dev-notion-setup`."

Store:
- `UAT_DB_ID` = `notion.uat_database_id`

---

## Step 2 — Which Feature Areas?

Ask the BA:
> "Which Feature Areas do you want to pull? You can say 'all' or name specific ones: POGSplit, LifecycleManagement, FloorPlanning, SpacePlanning."

Store the selection as `AREAS`. If "all", fetch every row.

---

## Step 3 — Ask for file path

Ask the BA:
> "Where do you want to save the Excel file? Paste the full path (e.g. `C:\Users\you\Documents\Academy_UAT.xlsx`). If the file already exists it will be overwritten."

Store as `EXCEL_PATH`.

---

## Step 4 — Fetch from Notion

Use `notion-query-data-sources` to fetch all rows from `UAT_DB_ID` where Feature Area is in `AREAS`.

For each row capture:
- `url` (Notion page URL — unique identifier)
- `Test Case`
- `Feature Area`
- `Steps`
- `Expected Result`
- `Notes`
- `Manual Status`
- `Final Sign-off`
- `Sign-off By`
- `Automated Status` (read-only reference — exported for BA visibility, not for editing)
- `createdTime`
- `lastEditedTime` (critical — stored in _SyncMeta for conflict detection)

Store all rows as `NOTION_ROWS`.

---

## Step 5 — Write Excel using PowerShell

```powershell
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel

$path = "EXCEL_PATH"   # substituted by Claude

# Remove existing file so we start clean
if (Test-Path $path) { Remove-Item $path -Force }

# Write one sheet per Feature Area
# $rows is injected by Claude as a JSON string, parsed here
$rows = $notionRows  # Claude provides this as a PowerShell array

$rows | Group-Object 'Feature Area' | ForEach-Object {
    $featureArea = $_.Name
    $sheetRows   = $_.Group | Select-Object 'Test Case','Steps','Expected Result','Notes','Manual Status','Final Sign-off','Sign-off By','Automated Status'
    $sheetRows | Export-Excel -Path $path -WorksheetName $featureArea -AutoSize -TableName ("tbl_" + ($featureArea -replace '\s',''))
}

# Write _SyncMeta sheet — one row per Notion row, used by import for conflict detection
$meta = $rows | Select-Object @{N='NotionUrl';E={$_.url}}, @{N='TestCase';E={$_.'Test Case'}}, @{N='LastEditedTime';E={$_.lastEditedTime}}
$meta | Export-Excel -Path $path -WorksheetName '_SyncMeta' -AutoSize

# Write _PullInfo sheet — one row with pull-level metadata
[PSCustomObject]@{
    PullTimestamp = (Get-Date -Format 'o')
    DatabaseId    = "UAT_DB_ID"
    Areas         = "AREAS_CSV"
    RowCount      = $rows.Count
} | Export-Excel -Path $path -WorksheetName '_PullInfo' -AutoSize

Write-Host "Done. $($rows.Count) rows written to $path"
```

If ImportExcel fails, tell the BA:
> "ImportExcel module couldn't be installed. Check that you have internet access and PowerShell can install modules (`Install-Module ImportExcel -Scope CurrentUser`). If you're on a managed machine, ask IT to install it."

---

## Step 6 — Confirm

> "Done. [N] test cases written to `[EXCEL_PATH]`:
>  - [Sheet list with row counts per Feature Area]
>
> **Edit the data sheets only** — do not touch `_SyncMeta` or `_PullInfo` or the import guard won't work.
> When you're done editing, run `/ba-uat-import` and provide this same file path."

---

</task>

<output>

## Editing rules to share with the BA

| Column | Can BA edit? |
|---|---|
| Test Case | Yes |
| Steps | Yes |
| Expected Result | Yes |
| Notes | Yes |
| Manual Status | Yes |
| Final Sign-off | Yes |
| Sign-off By | Yes |
| Automated Status | **No** — reference only, Playwright owns this |
| _SyncMeta sheet | **No** — import guard reads this |
| _PullInfo sheet | **No** — import guard reads this |

Add rows → new test cases. Delete rows → will show as orphaned on import (BA confirms before delete). Change Feature Area column → moves the row to a different area on import.

</output>
