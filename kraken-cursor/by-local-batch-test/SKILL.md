---
name: kraken-cursor-by-local-batch-test
description: >-
  Locally tests BlueYonder (BY/JDA) SaaS batch export scripts without Azure Key
  Vault. Use when a developer wants to run or test a BY batch export script
  (POG export, FLR export, or any cx_*.ps1 script) locally, when they mention
  "test the export", "run the batch script locally", "bypass Azure", "set globals",
  "test without Key Vault", or "update my batch test server/credentials". Manages
  per-developer local credentials in LocalTest/creds.json (gitignored).
---

# kraken-cursor: by-local-batch-test

**Announce at start:** "I'm using kraken-cursor-by-local-batch-test to run the batch export locally."

Runs BY SaaS batch export scripts locally by pre-setting the PowerShell globals that `set_db.ps1` checks — bypassing Azure Key Vault without modifying any scripts.

## How it works

`set_db.ps1` only fetches credentials from Azure if `$Global:HuCKBPassword` and `$Global:DBVMName` are not already set. By setting them first, the Azure block is skipped entirely and the exe gets its connection string from the env vars that `set_env.ps1` populates from those globals.

## Credential store

Each developer has their own `{repoRoot}/LocalTest/creds.json`. This file is gitignored — credentials are never committed. Every developer manages their own copy.

```json
{
  "DBVMName": "server\\instance",
  "HuCKBPassword": "..."
}
```

## Step 1 — Resolve credentials

Check `{repoRoot}/LocalTest/creds.json`.

**If file exists:**

- Show the current server: `"Using saved creds for <server> — run with these? (yes / update)"`
- If user says update (or if they asked to update server/creds): go to prompt flow below
- If yes: proceed with saved creds

**If file does not exist (first time / new developer):**

- Say: `"No local creds found. Let's set them up — this only needs to happen once per machine."`
- Prompt for:
  - **DB Server** (`DBVMName`) — e.g. `cx-lpt676\v2022`
  - **DB Password** (`HuCKBPassword`)
- Create `{repoRoot}/LocalTest/` directory if it doesn't exist
- Save to `{repoRoot}/LocalTest/creds.json`
- Remind: `"Saved to LocalTest/creds.json — this file is gitignored and won't be committed."`

**If user asks to update server or creds at any point:**

- Load existing file if present, show current values
- Prompt for new values (hit Enter to keep existing)
- Save and confirm

## Step 2 — Find available export scripts

Read `{repoRoot}/client.json`. Find entries where `target` is `batch`.
For each, check if a `cx_*.ps1` file exists in `F:\batch\exe\<project-name>\`.

If `client.json` doesn't exist or F: drive isn't accessible, ask the user for the script path directly.

## Step 3 — Ask which export to run

List available scripts and ask: which to run (e.g. POG, FLR, or both).

## Step 4 — Run the script(s)

For each selected script, invoke PowerShell with globals pre-set via Shell:

```powershell
$Global:DBVMName      = "<DBVMName>"
$Global:HuCKBPassword = "<HuCKBPassword>"
& "F:\batch\exe\<ProjectName>\cx_<type>_export.ps1"
```

Run sequentially if multiple selected. Capture full stdout and stderr for each.

## Step 5 — Report results

Show the full output for each script. Flag errors clearly.

Common errors and what they mean:

| Error | Cause | Fix |
|---|---|---|
| `CONNECTIONSTRING parameter missing` | Globals not picked up by set_env.ps1 | Check set_env.ps1 path in the PS script |
| `Could not load file or assembly` | Missing DLL in deploy folder | Redeploy from Academy portal |
| `Connect-AzAccount not recognized` | Az module missing — globals bypassed Azure but something re-ran set_db.ps1 | Check for double dot-source |
| Exit 0 with no output | Exe ran but export proc returned no rows | Check KEYPROCEDURE and DB data |
