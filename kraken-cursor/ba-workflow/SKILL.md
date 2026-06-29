---
name: kraken-cursor-ba-workflow
description: >-
  Loads Business Analyst domain context for the Academy/BlueYonder project — requirements,
  user stories, UAT test cases, and sign-off formats aligned with the Notion database schema.
  Use when a BA asks to draft requirements, write UAT test cases, structure sign-off notes,
  or describe feature behavior. Invoke with Use kraken-cursor-ba-workflow at the start of any
  BA session.
---

# kraken-cursor: ba-workflow

**Announce at start:** "I'm using kraken-cursor-ba-workflow for BA context on this project."

Helps a **Business Analyst** on the Academy BlueYonder (JDA Intactix) project. BAs own requirements, functional specs, UAT test cases, and sign-off. All BA documents live in **Notion**. This skill helps BAs write, refine, and structure content for Notion — it does not write code.

## Project domain

The Academy integration connects a retail client to the **BlueYonder (JDA) Intactix** suite:

- **Open Access** — web-based UI controls embedded in the Intactix portal
- **POGSplit** — splits a planogram (store layout plan) into child versions per store
- **Lifecycle Management** — manages planogram status transitions (draft → approved → active → archived)
- **Space Planning** — controls physical product placement on shelves
- **Floor Planning** — controls fixture and department layout across the store floor

**Key terms:**

| Term | Meaning |
|------|---------|
| Planogram (POG) | A diagram showing how products should be placed on a shelf |
| Store assignment | Linking a planogram to a specific store location |
| WIP | Work In Progress — a planogram in draft/editing state |
| DBKey | The system's internal ID number for any record |
| CKB | Category Knowledge Base — the central database |
| OA | Open Access — the web UI layer |

## Pre-flight

1. Resolve `{repoRoot}` = client repo root (where `docs/ba-config.json` or `.sln` lives).
2. All Notion operations use the **plugin-notion-workspace-notion** MCP server. Read tool schemas under the MCP descriptors before calling `CallMcpTool`.
3. If authentication fails, call `mcp_auth` for that server once, then retry.

## Writing requirements

Use this format for each requirement:

```
**ID:** REQ-[number]
**Feature:** [POGSplit | LifecycleManagement | FloorPlanning | SpacePlanning]
**Title:** One-line description
**As a** [role], **I want** [goal], **so that** [business value].

**Acceptance criteria:**
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

**Notes:** Any clarifications, edge cases, or open questions.
```

To write a requirement to Notion, use **Use kraken-cursor-ba-requirement**.

## Writing UAT test cases

Each test case maps to a row in the **Notion UAT database**. Use this structure:

```
**Test Case:** [short name matching what will appear in Notion]
**Feature Area:** [POGSplit | LifecycleManagement | FloorPlanning | SpacePlanning]
**Steps:**
1. Step one
2. Step two
3. Step three

**Expected Result:** Exactly what should happen if the test passes.
**Notes:** Edge cases, prerequisites, or data setup needed.
```

**Tips for good test cases:**

- Steps should be observable actions (click, navigate, enter a value) — not abstract descriptions
- Expected Result is what you *see*, not what you *hope for*
- One test case = one scenario. Don't combine multiple flows into one test.
- If a test requires specific data (a planogram DBKey, a store number), note it in the Notes field.

To generate UAT cases from the SDD, use **Use kraken-cursor-ba-generate-uat**.

## Running UAT tests

Before signing off, run the tests in the UAT portal:

1. Open the client portal HTML in `{repoRoot}` (e.g. `Academy.html`) → UAT tab
2. If the server isn't running, start it from the portal or ask the user to start the local dev server
3. Once the server is up, click **Open UAT Portal ↗**
4. Select the test cases you want to run by feature area and click **Run**
5. Review pass/fail results — then proceed to sign-off

For automated Playwright runs, use **Use kraken-cursor-qa-uat**.

If tests show as "Not Run" and the cache looks stale, use **Use kraken-cursor-ba-uat-pull** to pull fresh cases from Notion before running.

## Writing sign-off notes

When signing off in Notion, fill the **Notes** field if anything is worth recording:

- If Automated Status = Pass and you observed the same → sign off with a quick "Confirmed via manual walk-through on [date]"
- If Automated Status = Pass but you saw something different → fill Manual Status = Fail, explain what you observed, link a screenshot if possible
- If test is blocked by missing data or environment → fill Notes with what's missing; leave sign-off unchecked

To record results in Notion, use **Use kraken-cursor-ba-signoff**.

## Escalating to dev

Flag something to dev when:

- A test fails and you can reproduce it consistently
- The system behavior matches the spec but the spec seems wrong
- You need specific test data (DBKeys, planograms with certain properties) set up

When escalating, provide: what you did, what you expected, what you got, any error messages visible on screen.

## BA reference guides

Two HTML guides live in the repo and should be opened in a browser when onboarding a BA or reviewing the workflow:

| Guide | Path |
|---|---|
| BA Notion Guide (7-section onboarding) | `{repoRoot}/docs/html/ba-notion-guide.html` |
| BA Process Flow (swimlane diagram) | `{repoRoot}/docs/html/ba-process-flow.html` |

Open with the OS default browser (Windows: `start`, macOS: `open`).

## Available BA skills

These skills handle the full workflow autonomously — including reading from Notion and writing back:

| Skill | What it does |
|---|---|
| **Use kraken-cursor-ba-workflow** | This skill — loads domain context. Run at the start of any session. |
| **Use kraken-cursor-ba-generate-uat** | Reads the SDD from Notion + tech spec from GitHub, drafts UAT test cases, reviews with the BA, writes approved cases to the Notion UAT database. |
| **Use kraken-cursor-ba-requirement** | Turns a description, email, or meeting notes into a structured requirement with acceptance criteria, writes it to Notion. |
| **Use kraken-cursor-ba-signoff** | Finds a UAT test case in Notion, records manual observation (Pass/Fail/Notes), optionally marks Final Sign-off. |
| **Use kraken-cursor-ba-uat-pull** | Exports the current Notion UAT database to a local Excel file (one sheet per Feature Area). Always run this before editing Excel. Writes a sync stamp so import can detect conflicts. |
| **Use kraken-cursor-ba-uat-import** | Reads a local Excel file and syncs it back to Notion (new/updated/orphaned). If pulled with **Use kraken-cursor-ba-uat-pull** first, detects and resolves rows edited in Notion while the BA was working. |

All skills read `{repoRoot}/docs/ba-config.json` for Notion database IDs. If that file isn't configured yet, the skill stops safely and tells the BA to ask dev to run **Use kraken-cursor-dev-notion-setup**.

## Constraints

- Cannot access or control the live BlueYonder system
- Cannot run Playwright tests directly (dev/CI or **Use kraken-cursor-qa-uat** does this)
- Cannot make code changes — those go to the dev team
