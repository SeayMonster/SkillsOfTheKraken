---
name: switch-database
description: >
  Switch the mssql MCP server's connection between local and client environments
  (different SQL Server hosts, instances, ports, databases, or auth modes). Use
  this skill whenever the user asks to "switch to <env/db>", "go back to local",
  "use the client connection", "point sql at <server>", "swap the SQL MCP", or
  pastes a connection string for a different environment than the one currently
  configured. Handles the remove + re-add cycle for the `mssql-server` MCP entry,
  detects the local hostname from $env:COMPUTERNAME, and supports both Windows
  Integrated and SQL login auth. Works for any developer — never assume a
  specific server name or named instance; always prompt.
---

<context>
# Switch SQL MCP Connection

## Overview

The `mssql-server` MCP entry locks its connection at startup via environment variables. To repoint it at a different SQL Server, instance, port, database, or auth mode, remove the entry and re-add it with new env vars, then have the user restart Claude Code.

This skill is designed to work for any developer on the team — local machine names, named instances, and default-instance setups all vary, so the skill **always asks** rather than assumes.

## When to Use

Trigger any time the user says or implies a connection swap:

- "Switch to <db>", "go back to local", "use my local DB"
- "Use the client connection", "switch to <client name>", "point sql at <server>"
- "Use SQL login auth", "switch to Windows auth"
- Pastes an ADO/.NET connection string and asks to use it
- Mentions a database/server that doesn't match the current `mssql-server` entry (check with `/mcp` if uncertain)

**Do not use for:**
- Querying a different database on the **same server** — qualify the table name (`otherdb.schema.TableName`). The existing connection's account already has access; no MCP reconfig needed.
- One-off cross-database joins.
</context>

<task>
## "Back to Local" Workflow

When the user says "back to local" (or similar), do **not** assume any hostname or instance — different teammates have different setups (some have multiple named instances, most don't).

Steps:

1. **Get hostname automatically** in PowerShell — do not ask the user for it:

   ```powershell
   $env:COMPUTERNAME
   ```

2. **Ask the user for the instance**, with the default instance as the suggestion:

   > "Instance name? (Press Enter for the default instance, or type a named instance like `v2022` or `SQLEXPRESS`)"

3. **Ask the user for the database name** (no default — always prompt).

4. **Construct the server string:**
   - Default instance → just `<COMPUTERNAME>`
   - Named instance → `<COMPUTERNAME>\<instance>`

5. **Run the swap** using the Windows-auth template below. Local dev is always Windows Integrated unless the user says otherwise.

## "Switch to Client Environment" Workflow

For non-local environments, ask for everything — never reuse local defaults:

1. **Server** — full hostname, named instance, or `host,port` (e.g. `acme-sql-01.client.com`, `prod-db,1433`, `host\instance`)
2. **Database** — target database name
3. **Auth mode:**
   - Windows Integrated (rare for client envs)
   - SQL login (most common) → ask for username and how the password is supplied (env var preferred over plaintext)
4. **Driver** (rarely changes) — assume `ODBC Driver 17 for SQL Server` unless the user says otherwise
5. **Encryption** (only if the client requires it, usually with ODBC 18 or strict TLS policies) — `MSSQL_ENCRYPT=yes`, optionally `MSSQL_TRUST_SERVER_CERTIFICATE=yes`

If the user pastes a `.NET`/ADO connection string, parse and confirm:
- `Server=` → `MSSQL_SERVER`
- `Database=` or `Initial Catalog=` → `MSSQL_DATABASE`
- `Integrated Security=true|SSPI|yes` → Windows auth
- `User Id=` / `Password=` → SQL auth (still ask whether to read the password from an env var instead of pasting it)
- `Encrypt=true` → `MSSQL_ENCRYPT=yes`
- `TrustServerCertificate=true` → `MSSQL_TRUST_SERVER_CERTIFICATE=yes`

## Swap Templates

Always remove first, then add. `claude mcp add` will not overwrite an existing entry of the same name.

**Windows Integrated auth (typical for local dev):**

```powershell
claude mcp remove mssql-server
claude mcp add --transport stdio --env MSSQL_SERVER=<server> --env MSSQL_DATABASE=<database> --env MSSQL_DRIVER="ODBC Driver 17 for SQL Server" --env MSSQL_TRUSTED_CONNECTION=true mssql-server -- python -m mssql_mcp_server
```

**SQL login auth (typical for client environments):**

```powershell
claude mcp remove mssql-server
claude mcp add --transport stdio --env MSSQL_SERVER=<server> --env MSSQL_DATABASE=<database> --env MSSQL_USER=<user> --env MSSQL_PASSWORD=<password-or-$env:VAR_NAME> --env MSSQL_DRIVER="ODBC Driver 17 for SQL Server" mssql-server -- python -m mssql_mcp_server
```

After the swap:
- Tell the user to restart Claude Code (full window reload — VS Code extension or desktop app). MCP config only loads at startup.
- Ask them to verify with `/mcp` — `mssql-server` should be listed and connected to the new target.

## Optional: PowerShell Profile Shortcuts

If the user repeatedly swaps between the same environments, suggest adding profile functions to `$PROFILE` so each swap is one command. Pattern:

```powershell
function Use-SqlMcp-Local {
  param([string]$Database)
  claude mcp remove mssql-server 2>$null
  $server = "$env:COMPUTERNAME"  # add `\v2022` etc. if you have a named instance
  claude mcp add --transport stdio --env MSSQL_SERVER=$server --env MSSQL_DATABASE=$Database --env MSSQL_DRIVER="ODBC Driver 17 for SQL Server" --env MSSQL_TRUSTED_CONNECTION=true mssql-server -- python -m mssql_mcp_server
}

function Use-SqlMcp-Client-Acme {
  claude mcp remove mssql-server 2>$null
  claude mcp add --transport stdio --env MSSQL_SERVER=acme-sql-01,1433 --env MSSQL_DATABASE=AcmeProd --env MSSQL_USER=svc_reader --env MSSQL_PASSWORD=$env:ACME_SQL_PWD --env MSSQL_DRIVER="ODBC Driver 17 for SQL Server" mssql-server -- python -m mssql_mcp_server
}
```

Never hardcode plaintext SQL passwords in `$PROFILE` or commit them to a repo. Read from an environment variable or a credential store (`Get-Secret`, Windows Credential Manager) instead.
</task>

<constraints>
## Common Mistakes

- **Assuming a specific local hostname or instance** — varies per developer. Always pull from `$env:COMPUTERNAME` and prompt for the instance.
- **Forgetting to restart Claude Code** — MCP config only reloads on startup. Tell the user explicitly.
- **Adding before removing** — `claude mcp add` will not overwrite an existing entry. Always remove first.
- **Hardcoding client passwords** — never put plaintext SQL passwords in `$PROFILE` or commit them. Use env vars or a credential manager.
- **Reconfiguring for same-server, different-DB queries** — three-part naming (`db.schema.table`) is faster than swapping the MCP entry when the database lives on the same instance.
- **Wrong driver string** — must be exactly `ODBC Driver 17 for SQL Server` (with quotes in PowerShell). Driver 18 works if installed but enforces encryption — may need `MSSQL_ENCRYPT=yes` and `MSSQL_TRUST_SERVER_CERTIFICATE=yes` for self-signed certs.
- **Backslash / comma escaping in server names** — `host\instance` and `host,port` go in raw as a single PowerShell argument; no extra escaping needed when passed via `--env`.
- **Mixing Windows auth and SQL auth env vars** — if `MSSQL_TRUSTED_CONNECTION=true` is set, `MSSQL_USER`/`MSSQL_PASSWORD` are ignored (and vice versa). Pick one mode cleanly.
</constraints>
