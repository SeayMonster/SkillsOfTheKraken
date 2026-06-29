---
name: create-deployment-package
description: >
  Generate a deployment package for a SaaS CKB SQL Server client.
  Reads _package-request.json written by the portal. Orchestrates a
  multi-agent workflow to gather changes per project, build a combined
  SQL script + README, generate deployment guides, and produce a ZIP
  handoff package (--saas) or commit only (--local).
---

<context>
Invoke as:
```
/kraken:create-deployment-package --saas
/kraken:create-deployment-package --local
```

If invoked without a flag, ask: "Which mode? `--saas` (generate ZIP handoff package for deployment team) or `--local` (commit and push only — portal handles local deploy)?" Do not proceed until the user specifies.

**Announce at start:** "I'm using the create-deployment-package skill to build the deployment package."
</context>

<task>
## Pre-flight checks

1. Validate flag is `--saas` or `--local`. If missing, ask the user (see above).

2. Read `_package-request.json` from the repo root. Stop if:
   - File missing → "`_package-request.json` not found. Generate it from the portal before running this skill."
   - `projects` empty or missing → "No projects selected. Choose at least one project in the portal."
   - `environment` missing or null → "`environment` is required in `_package-request.json`."

3. Read `Environment Details/env-config.json`. If no entry matches the `environment` value from `_package-request.json`, stop:
   "`env-config.json` has no entry for `[environment value]`. Add server/database details first."
   (This check applies to both `--saas` and `--local` — the workflow needs server/db for the README regardless of flag.)

4. Determine the absolute path to the current repo root (the directory containing `_package-request.json`).

5. Announce: "Using create-deployment-package workflow..."

6. Invoke the Workflow:

```
Workflow({
  scriptPath: "C:\\Users\\bseay\\source\\repos\\SkillsOfTheKraken\\skills\\create-deployment-package\\workflow.js",
  args: { flag: "<--saas or --local>", repoRoot: "<absolute path to repo root>" }
})
```
</task>

<constraints>
| Scenario | Action |
|---|---|
| No flag provided | Ask before proceeding |
| `_package-request.json` missing | Stop with message |
| `projects` empty | Stop with message |
| `environment` missing | Stop with message |
| env not in env-config.json (either flag) | Stop with message showing actual value |
</constraints>
