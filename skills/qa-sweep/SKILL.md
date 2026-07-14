---
name: qa-sweep
description: >
  Config-driven multi-agent QA sweep of a project before handoff. Verifies data
  correctness (SQL vs UI) first, then UI/API/visual/WPF, produces a ranked report
  with screenshots, and detects drift against a golden baseline on re-runs. Use when
  the user wants to test all functionality of an app, run a pre-handoff QA gate, or
  says "qa sweep", "test the site", "test everything before handoff". Reads
  qa-sweep.config.json from the repo root.
---

# QA-Sweep

## Step 1 — Locate and validate config

Read `qa-sweep.config.json` from the repo root. If missing, tell the user to create one
(point at `config.schema.json` in this skill dir) and stop. Validate it parses.

## Step 2 — Ensure the app is running

Confirm the app at `config.launch.baseUrl` responds. If not, start it via
`preview_start` using `config.launch.name`.

## Step 3 — Prompt for depth + run mode (main thread, before launch)

First, AskUserQuestion for **depth**:
- **full** (default) — complete pre-handoff gate: correctness + UI + API + full screenshot matrix + WPF + baseline/drift.
- **smoke** — fast dev loop (~3 min): correctness + UI + API only. No screenshot matrix, no WPF, no baseline/drift; UI agents capture a screenshot only when a page is broken (failure evidence).

Then AskUserQuestion for **run mode** (governs the exploratory loop):
- **once** — core deterministic suite only (default)
- **until-dry** — core + exploratory until N dry rounds (then ask N, default 2)
- **budget** — core + exploratory until a token cap. Recommend `CORE_ESTIMATE + pages*combos*PER_COMBO_BUDGET`
  (site-size based, NOT last failures). Show recommended and a ceiling of 3x recommended; clamp any larger input.
- **count** — exploratory N times (then ask N)

Map answers to `depth` (`full|smoke`), `mode` (`once|dry|budget|count`) and `limit`.
Mechanical agents (discovery/UI/API/visual/WPF/exploratory) always run on Haiku; correctness/verify/synthesis stay on the session model.

## Step 4 — Launch the workflow

```
Workflow({
  scriptPath: "{SKILL_DIR}/workflow.js",
  args: { config: <parsed qa-sweep.config.json>, depth: <depth>, mode: <mode>, limit: <limit>, now: "<ISO date>" }
})
```

## Step 5 — Surface the result

When the workflow completes, report the gate (PASS/FAIL), failure count, and the
report path (`config.reportPath/report-latest.md`). On first successful run, tell the
user they can bless the baseline by re-running with the baseline accept step.
