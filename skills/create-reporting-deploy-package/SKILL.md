---
name: create-reporting-deploy-package
description: >
  Generate an IIS deploy package for any ASP.NET Core project.
  Auto-detects the web project and target framework from cwd.
  On first run, prompts for environment/server/connection string and
  writes _deploy-request.json. Produces a ZIP handoff package
  (publish artifacts + web.config + appsettings.Production.json + DEPLOY-README.md).
---

<context>
Invoke as:
```
/kraken:create-reporting-deploy-package
```

Run from the repo root of the target ASP.NET Core project.

**Announce at start:** "I'm using the create-reporting-deploy-package skill to build the IIS deploy package."
</context>

<task>
## Pre-flight checks

1. Read `_deploy-request.json` from cwd. If the file does not exist:
   a. Ask: "No `_deploy-request.json` found. Let me create one. What is the target environment name? (e.g. production, staging)"
   b. Ask: "What is the target server hostname? (e.g. myserver.domain.com)"
   c. Ask: "What is the SQL Server connection string?"
   d. Write `_deploy-request.json` to cwd with the provided values. Use `"CrispReporting"` as the default for both `iisSiteName` and `iisAppPool`:
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

4. Determine the absolute path to cwd (repo root).

5. Announce: "Using create-reporting-deploy-package workflow..."

6. Invoke the Workflow:

```
Workflow({
  scriptPath: "C:\\Users\\bseay\\source\\repos\\SkillsOfTheKraken\\skills\\create-reporting-deploy-package\\workflow.js",
  args: { repoRoot: "<absolute path to cwd>" }
})
```
</task>

<constraints>
| Scenario | Action |
|---|---|
| `_deploy-request.json` missing | Prompt 3 questions, write file, proceed |
| `environment` missing from config | Stop: "`environment` is required in `_deploy-request.json`." |
| `serverName` missing from config | Stop: "`serverName` is required in `_deploy-request.json`." |
| `connectionString` missing from config | Stop: "`connectionString` is required in `_deploy-request.json`." |
| No web .csproj found | Workflow stops: "No ASP.NET Core web project found in cwd." |
| Multiple web .csproj found | Workflow stops and asks user to add `projectPath` to `_deploy-request.json` |
| `dotnet build` fails | Workflow stops with build error output |
| `dotnet publish` fails | Workflow stops with publish error output |
| ZIP output path not accessible | Warn, write ZIP to cwd instead |
</constraints>
