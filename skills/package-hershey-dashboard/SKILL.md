---
name: package-hershey-dashboard
description: >
  Build, package, and deploy the Hershey H.-Reports WPF dashboard and its
  ReportingDashboard SQL. Spawns agents to publish + zip the WPF app
  (Publish-HersheyDashboard.ps1), validate the package contents, and run the
  CrispReporting SQL install (Deploy-ReportingSql.ps1). Use this whenever the
  user wants to deploy, package, publish, ship, or cut a zip for the Hershey
  Dashboard / HersheyDashboard / H.-Reports WPF app, hand a build to the RDP
  box, or install/deploy the reporting SQL — even if they don't say "package".
  Not portal/SaaS-driven: there is no _package-request.json here; the target
  DB server is read from connectionStrings.local.config at runtime.
---

<context>
Invoke as:
```
/package-hershey-dashboard --build   # publish the WPF app + zip it (default)
/package-hershey-dashboard --sql     # deploy the ReportingDashboard SQL (CrispReporting)
/package-hershey-dashboard --all     # build the app AND deploy the SQL
```

If invoked without a flag, ask: "Which mode? `--build` (publish + zip the WPF app), `--sql` (deploy the reporting SQL), or `--all` (both)?" If the user just says "package/deploy the dashboard" with no other signal, default to `--build`.

**Announce at start:** "I'm using the package-hershey-dashboard skill to build the deployment package."

This skill is a thin orchestrator. The real work lives in two PowerShell scripts **inside the target repo** (not in this skill), so the deploy logic is versioned with the app:
- `HersheyDashboard/deploy/Publish-HersheyDashboard.ps1` — build/publish WPF + zip
- `ReportingDashboard/sql/deploy/Deploy-ReportingSql.ps1` — deploy CrispReporting SQL
The agents invoke those; this skill just sequences them and validates the result.
</context>

<task>
## Core rules

1. **Scripts are the source of truth** — never re-implement build/zip/SQL logic here. Invoke the two repo scripts. If a script is missing, stop and say so (the repo may be on the wrong branch).
2. **Never ship the per-machine config** — `Publish-HersheyDashboard.ps1` deliberately excludes `connectionStrings.local.config` so it can't clobber the target box's connection. The Validate phase enforces this; if the config appears in the package, fail.
3. **SQL is dry-run by default** — `Deploy-ReportingSql.ps1` makes no changes without `-Execute`. Only pass `--execute` when the user has explicitly confirmed they want to write to the server (it can create the `CrispReporting` database on a live Hershey box — an outward, hard-to-reverse action).
4. **Server comes from config, not a portal** — the SQL script parses the server from the `Ckb` entry in `connectionStrings.local.config`. There is no `_package-request.json` / `env-config.json` in this repo; do not look for them.

## Pre-flight checks

1. Validate the flag is `--build`, `--sql`, or `--all`. If missing, ask (see above).

2. Determine the absolute path to the target repo root (the H.-Reports repo — the directory containing `HersheyDashboard/` and `ReportingDashboard/`). This is `repoRoot`.

3. Confirm the script(s) the chosen flag needs exist:
   - `--build` / `--all` → `repoRoot\HersheyDashboard\deploy\Publish-HersheyDashboard.ps1`
   - `--sql` / `--all` → `repoRoot\ReportingDashboard\sql\deploy\Deploy-ReportingSql.ps1`
   If a required script is missing, stop: "Deploy script not found at `<path>` — is the repo on the feature branch that added it?"

4. For `--sql` / `--all`, confirm `repoRoot\HersheyDashboard\connectionStrings.local.config` exists (the SQL script parses the server from it). If absent, stop and tell the user to create it (or pass an explicit server).

5. Announce the skill (see above).

6. Invoke the Workflow, passing the flag, repo root, and any confirmed switches:

```
Workflow({
  scriptPath: "C:\\Users\\bseay\\source\\repos\\SkillsOfTheKraken\\skills\\package-hershey-dashboard\\workflow.js",
  args: {
    flag: "<--build | --sql | --all>",
    repoRoot: "<absolute path to H.-Reports repo root>",
    execute: <true only if the user confirmed a real SQL deploy; else false>,
    selfContained: <true if the target box lacks the .NET 8 Desktop Runtime; else false>,
    skipSeed: <true to skip the mock seed data; else false>
  }
})
```

## Phases (what the workflow does)

| Phase | Runs | Agent returns |
|-------|------|---------------|
| **Build** (`--build`/`--all`) | `Publish-HersheyDashboard.ps1` | zip path, file count, built-DLL timestamp |
| **Validate** (`--build`/`--all`) | inspects the produced zip | exe/dll/HersheyDashboard.html present, `connectionStrings.local.config` absent |
| **SQL** (`--sql`/`--all`) | `Deploy-ReportingSql.ps1` (dry-run unless `execute`) | server parsed from config, dry-run plan or deploy receipt |

If Validate fails, the workflow throws before any SQL runs — report the issues and stop.

## After the workflow

Report to the user, verbatim where useful:
- The **zip path** to copy to the RDP box (for `--build`/`--all`).
- Whether the SQL was a **dry run** or an actual deploy, and which **server** it targeted.
- Reminder: on the RDP box, unzip and ensure `connectionStrings.local.config` exists next to the exe (the package ships only the `.template`).
</task>

<constraints>
| Scenario | Action |
|---|---|
| No flag provided | Ask before proceeding |
| Required deploy script missing | Stop — repo may be on the wrong branch |
| `--sql`/`--all` and no `connectionStrings.local.config` | Stop — need a server to target |
| SQL `--execute` requested without explicit user confirmation | Do NOT pass `execute:true`; run dry-run and ask first |
| Validate finds `connectionStrings.local.config` in the package | Fail — it must never ship |
| Validate finds exe/dll/html missing | Fail — build is broken |
</constraints>
