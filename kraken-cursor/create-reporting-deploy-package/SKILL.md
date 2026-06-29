---
name: kraken-cursor-create-reporting-deploy-package
description: >-
  Cursor adapter for IIS deploy packages for ASP.NET Core projects. Reads
  _deploy-request.json, orchestrates multi-phase Task subagents (Validate,
  Publish, Configure, Package), and produces a ZIP handoff package with
  publish artifacts, web.config, appsettings.Production.json, and
  DEPLOY-README.md. Use when the user asks for a reporting deploy package,
  IIS deploy package, kraken-cursor reporting deployment, or
  create-reporting-deploy-package in Cursor.
---

# kraken-cursor: create-reporting-deploy-package

**Announce at start:** "I'm using kraken-cursor-create-reporting-deploy-package to build the IIS deploy package."

This skill replaces Claude Code's `Workflow()` with **Task subagents** and shell commands. Do not call `Workflow()`.

## Invoke

User request examples:
- "create reporting deploy package"
- "build IIS deploy package"
- "kraken-cursor reporting deployment"

Run from the repo root of the target ASP.NET Core project.

## Pre-flight (parent agent — stop on failure)

1. Read `{repoRoot}/_deploy-request.json`. If the file does not exist:
   a. Ask: "No `_deploy-request.json` found. Let me create one. What is the target environment name? (e.g. production, staging)"
   b. Ask: "What is the target server hostname? (e.g. myserver.domain.com)"
   c. Ask: "What is the SQL Server connection string?"
   d. Write `_deploy-request.json` to `{repoRoot}` with the provided values. Use `"CrispReporting"` as the default for both `iisSiteName` and `iisAppPool`:
      ```json
      {
        "environment": "<answer from a>",
        "serverName": "<answer from b>",
        "connectionString": "<answer from c>",
        "iisSiteName": "CrispReporting",
        "iisAppPool": "CrispReporting"
      }
      ```

2. Validate config has all three required fields: `environment`, `serverName`, `connectionString`. Stop with a message identifying the missing field if any are absent.

3. Apply defaults: if `iisSiteName` absent → `"CrispReporting"`. If `iisAppPool` absent → `"CrispReporting"`.

4. Set `repoRoot` = directory containing `_deploy-request.json` (typically cwd).

5. Read `references/workflow-phases.md` in this skill folder for full phase prompts.

6. Resolve skill paths:
   - `SKILL_DIR` = directory containing this SKILL.md (installed at `~/.cursor/skills/kraken-cursor-create-reporting-deploy-package/` or repo `kraken-cursor/create-reporting-deploy-package/`)

7. Create state file `{repoRoot}/.kraken-cursor/deploy-state-working.json` (empty `{}`) for phase handoff.

8. Optional: read `batchDeployPath` from `_deploy-request.json` for ZIP output location. If absent, Phase 4 falls back to a path beside the publish directory.

## Orchestration overview

Execute phases **in order**. Pass outputs forward via the state file and Task return values.

| Phase | Parallelism | Tool |
|-------|-------------|------|
| 1 Validate | single | Task (generalPurpose) or parent |
| 2 Publish | single | Task |
| 3 Configure | appsettings + web.config | Task × 2 in one message |
| 4 Package | single | Task or parent + Shell |

## Phase execution

For each phase, use the matching section in `references/workflow-phases.md`. Substitute:
- `{repoRoot}`, `{SKILL_DIR}`, `{batchDeployPath}` (optional from `_deploy-request.json`)

After **Validate**, write to `{repoRoot}/.kraken-cursor/deploy-state-working.json` → key `validated`:
`projectPath`, `targetFramework`, `assemblyName`, `iisSiteName`, `iisAppPool`

After **Publish**, append key `publishDir` (absolute path).

After **Configure**, append key `configureComplete: true`.

After **Package**, report the full path to the created ZIP.

## Output

Report when complete:
- ZIP path: `{batchDeployPath}/{environment}-{date}.zip` or fallback beside publish dir
- Publish dir (temp): from state file `publishDir`
- Generated files in publish dir: `appsettings.Production.json`, `web.config`, `DEPLOY-README.md`

## Constraints

| Scenario | Action |
|----------|--------|
| `_deploy-request.json` missing | Prompt 3 questions, write file, proceed |
| `environment` missing from config | Stop: "`environment` is required in `_deploy-request.json`." |
| `serverName` missing from config | Stop: "`serverName` is required in `_deploy-request.json`." |
| `connectionString` missing from config | Stop: "`connectionString` is required in `_deploy-request.json`." |
| No web .csproj found | Stop: "No ASP.NET Core web project found in repo root." |
| Multiple web .csproj found | Stop; ask user to add `projectPath` to `_deploy-request.json` |
| `dotnet build` fails | Stop with build error output |
| `dotnet publish` fails | Stop with publish error output |
| Batch deploy path not accessible | Warn; write ZIP beside publish dir instead |

## Related

- Claude Code equivalent: `/kraken:create-reporting-deploy-package`
- Phase prompts: `references/workflow-phases.md`
