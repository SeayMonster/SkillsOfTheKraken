---
name: by-local-batch-test
description: >
  Locally test BlueYonder (BY/JDA) SaaS batch export scripts without Azure Key Vault.
  Use this skill whenever a developer wants to run or test a BY batch export script
  (POG export, FLR export, or any cx_*.ps1 script) locally, when they mention
  "test the export", "run the batch script locally", "bypass Azure", "set globals",
  "test without Key Vault", or "update my batch test server/credentials".
  The skill manages per-developer local credentials in LocalTest/creds.json (gitignored)
  and sets $Global:DBVMName and $Global:HuCKBPassword so set_db.ps1 skips Azure entirely.
---

# BY Local Batch Test

Runs BY SaaS batch export scripts locally by pre-setting the PowerShell globals
that `set_db.ps1` checks — bypassing Azure Key Vault without modifying any scripts.

## How it works

`set_db.ps1` only fetches credentials from Azure if `$Global:HuCKBPassword` and
`$Global:DBVMName` are not already set. By setting them first, the Azure block is
skipped entirely and the exe gets its connection string from the env vars that
`set_env.ps1` populates from those globals.

## Credential Store

Each developer has their own `LocalTest\creds.json` in the project root. This file
is gitignored — credentials are never committed. Every developer manages their own copy.

```json
{
  "DBVMName": "server\\instance",
  "HuCKBPassword": "..."
}
```

## Steps

### 1. Resolve credentials

Check `LocalTest\creds.json` in the project root.

**If file exists:**
- Show the current server: `"Using saved creds for <server> — run with these? (yes / update)"`
- If user says update (or if they asked to update server/creds): go to prompt flow below
- If yes: proceed with saved creds

**If file does not exist (first time / new developer):**
- Say: `"No local creds found. Let's set them up — this only needs to happen once per machine."`
- Prompt for:
  - **DB Server** (`DBVMName`) — e.g. `cx-lpt676\v2022`
  - **DB Password** (`HuCKBPassword`)
- Create `LocalTest\` directory if it doesn't exist
- Save to `LocalTest\creds.json`
- Remind: `"Saved to LocalTest\creds.json — this file is gitignored and won't be committed."`

**If user asks to update server or creds at any point:**
- Load existing file if present, show current values
- Prompt for new values (hit Enter to keep existing)
- Save and confirm

### 2. Find available export scripts

Read `client.json` in the project root. Find entries where `target` is `batch`.
For each, check if a `cx_*.ps1` file exists in `F:\batch\exe\<project-name>\`.

If `client.json` doesn't exist or F: drive isn't accessible, ask the user for the
script path directly.

### 3. Ask which export to run

List available scripts and ask: which to run (e.g. POG, FLR, or both).

### 4. Run the script(s)

For each selected script, invoke PowerShell with globals pre-set:

```powershell
$Global:DBVMName      = "<DBVMName>"
$Global:HuCKBPassword = "<HuCKBPassword>"
& "F:\batch\exe\<ProjectName>\cx_<type>_export.ps1"
```

Run sequentially if multiple selected. Capture full stdout and stderr for each.

### 5. Report results

Show the full output for each script. Flag errors clearly.

Common errors and what they mean:

| Error | Cause | Fix |
|---|---|---|
| `CONNECTIONSTRING parameter missing` | Globals not picked up by set_env.ps1 | Check set_env.ps1 path in the PS script |
| `Could not load file or assembly` | Missing DLL in deploy folder | Redeploy from Academy portal |
| `Connect-AzAccount not recognized` | Az module missing — globals bypassed Azure but something re-ran set_db.ps1 | Check for double dot-source |
| Exit 0 with no output | Exe ran but export proc returned no rows | Check KEYPROCEDURE and DB data |
