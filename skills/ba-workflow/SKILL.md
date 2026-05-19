---
name: ba-workflow
description: Business Analyst workflow for the Academy/BlueYonder project — writing requirements, user stories, and UAT test cases in formats that align with the Notion database schema. Use when a BA asks Claude to help draft requirements, write UAT test cases, structure sign-off notes, or describe feature behavior.
trigger: Use this skill when a BA asks for help writing requirements, user stories, acceptance criteria, UAT test cases, sign-off notes, or feature descriptions for the Academy BlueYonder project.
---

# BA Workflow — Academy / BlueYonder Project

<context>

## Your role

You are helping a **Business Analyst** on the Academy BlueYonder (JDA Intactix) project. BAs own:
- Requirements and user stories
- Functional specs
- UAT test cases and sign-off

All BA documents live in **Notion**. You help BAs write, refine, and structure content that goes into Notion — you do not write code.

---

## Project domain (what the system does)

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

---

</context>

<task>

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

---

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

---

## Running UAT tests

Before signing off, run the tests in the UAT portal:

1. Open **Academy Portal** (`Academy.html`) → UAT tab
2. If the server isn't running, say **start the UAT portal** in Claude Code
3. Once the server is up, click **Open UAT Portal ↗**
4. Select the test cases you want to run by feature area and click **Run**
5. Review pass/fail results — then proceed to sign-off

If tests show as "Not Run" and the cache looks stale, say **sync UAT tests** in Claude Code to pull fresh cases from Notion before running.

---

## Writing sign-off notes

When signing off in Notion, fill the **Notes** field if anything is worth recording:

- If Automated Status = Pass and you observed the same → sign off with a quick "Confirmed via manual walk-through on [date]"
- If Automated Status = Pass but you saw something different → fill Manual Status = Fail, explain what you observed, link a screenshot if possible
- If test is blocked by missing data or environment → fill Notes with what's missing; leave sign-off unchecked

---

## Escalating to dev

Flag something to dev when:
- A test fails and you can reproduce it consistently
- The system behavior matches the spec but the spec seems wrong
- You need specific test data (DBKeys, planograms with certain properties) set up

When escalating, provide: what you did, what you expected, what you got, any error messages visible on screen.

---

## BA reference guides

Two HTML guides live in the repo and should be opened in a browser when onboarding a BA or reviewing the workflow:

| Guide | Path |
|---|---|
| BA Notion Guide (7-section onboarding) | `docs/html/ba-notion-guide.html` |
| BA Process Flow (swimlane diagram) | `docs/html/ba-process-flow.html` |

Open them with: `start docs\html\ba-notion-guide.html` (Windows) or `open docs/html/ba-notion-guide.html` (Mac).

---

## Available BA commands

These skills handle the full workflow autonomously — including reading from Notion and writing back:

| Command | What it does |
|---|---|
| `/ba-workflow` | This skill — loads domain context. Run at the start of any session. |
| `/ba-generate-uat` | Reads the SDD from Notion + tech spec from GitHub, drafts UAT test cases, reviews with you, writes approved cases to the Notion UAT database. |
| `/ba-requirement` | Turns a description, email, or meeting notes into a structured requirement with acceptance criteria, writes it to Notion. |
| `/ba-signoff` | Finds a UAT test case in Notion, records your manual observation (Pass/Fail/Notes), optionally marks Final Sign-off. |
| `/ba-uat-pull` | Exports the current Notion UAT database to a local Excel file (one sheet per Feature Area). Always run this before editing your Excel. Writes a sync stamp so the import can detect conflicts. |
| `/ba-uat-import` | Reads your local Excel file and syncs it back to Notion (new/updated/orphaned). If you pulled with `/ba-uat-pull` first, automatically detects and resolves any rows edited in Notion while you were working. |

All commands read `docs/ba-config.json` for Notion database IDs. If that file isn't configured yet, the command will tell you and stop safely.

---

</task>

<constraints>

## What Claude cannot do for BAs

- Access or control the live BlueYonder system
- Run Playwright tests (dev/CI does this)
- Make code changes — those go to the dev team

</constraints>
