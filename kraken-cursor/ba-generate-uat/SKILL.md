---
name: kraken-cursor-ba-generate-uat
description: >-
  Generates UAT test cases for a feature by reading the SDD from Notion and the technical spec
  from GitHub, drafting cases in the Notion UAT database schema, reviewing with the BA, then
  writing approved cases to Notion. Use when a BA asks to generate, create, or draft UAT test
  cases, or says "set up UAT for [feature]" or "create test cases from the SDD". Invoke with
  Use kraken-cursor-ba-generate-uat.
---

# kraken-cursor: ba-generate-uat

**Announce at start:** "I'm using kraken-cursor-ba-generate-uat to draft UAT test cases."

Reads the SDD from Notion + the technical spec from GitHub, generates UAT test cases in the correct Notion schema, reviews the draft with the BA, then writes approved test cases to the Notion UAT database.

## Pre-flight

1. Resolve `{repoRoot}` = client repo root.
2. Read `{repoRoot}/docs/ba-config.json`.
   - If `notion.uat_database_id` still contains `REPLACE_WITH_`, STOP and tell the BA:
     > "The Notion config hasn't been filled in yet. Ask your dev to run **Use kraken-cursor-dev-notion-setup** or fill in `{repoRoot}/docs/ba-config.json` with the Notion database IDs. This is a one-time setup."
   - Then exit.
3. Store:
   - `UAT_DB_ID` = `notion.uat_database_id`
   - `SDD_PAGE_ID` = `notion.sdd_page_id`
4. Use the **plugin-notion-workspace-notion** MCP server for all Notion reads and writes. Read tool schemas before calling `CallMcpTool`. If authentication fails, call `mcp_auth` once, then retry.

## Steps

### Step 1 — Identify the feature

If the BA didn't specify a feature, ask:

> "Which feature are we generating test cases for? (POGSplit, LifecycleManagement, FloorPlanning, SpacePlanning, or another?)"

Map the answer to the corresponding GitHub spec file from `{repoRoot}/docs/ba-config.json` `github` section. If no spec file is mapped, use whatever is closest in `{repoRoot}/docs/superpowers/specs/`.

### Step 2 — Fetch the SDD from Notion

Use the Notion MCP fetch-page tool (server: `plugin-notion-workspace-notion`) with `page_id = SDD_PAGE_ID`.

If the fetch fails or the page is empty:

> "I couldn't read the SDD from Notion. Make sure `{repoRoot}/docs/ba-config.json` has the correct `sdd_page_id`. You can find it in the Notion page URL."

### Step 3 — Read the technical spec from GitHub

Read the mapped spec file from the repo. Extract:

- Feature description and purpose
- Business rules and constraints
- Data flow (what goes in, what comes out)
- Edge cases explicitly called out

### Step 4 — Generate test case drafts

Cross-reference the SDD (business intent) with the technical spec (system behavior). Generate test cases that cover:

1. **Happy path** — the primary success scenario
2. **Boundary conditions** — minimum/maximum values, empty sets, single-item sets
3. **Error cases** — what should fail gracefully and how
4. **State transitions** — before/after states (especially for LifecycleManagement status changes)

Format each test case exactly as follows — this matches the Notion UAT database schema:

```
TEST CASE: [Short descriptive name — this becomes the Notion row title]
Feature Area: [POGSplit | LifecycleManagement | FloorPlanning | SpacePlanning]
Steps:
  1. [Observable action]
  2. [Observable action]
  3. [Observable action]
Expected Result: [What the user sees/experiences when the system behaves correctly]
Notes: [Prerequisites, required test data (DBKeys etc.), known constraints]
```

Rules for good test cases:

- Steps are observable actions (click, navigate, enter a value) — not abstract intentions
- Expected Result is what you *see*, not what you *hope*
- One scenario per test case — no compound flows
- If a test needs a specific planogram DBKey or store, note it in Notes

Present the full draft list to the BA. Count how many were generated.

### Step 5 — BA review loop

After presenting the draft, ask:

> "Does this look right? You can ask me to add, remove, or reword any test case before I write them to Notion."

Accept and apply any feedback. Repeat until the BA says they're satisfied.

Do NOT write anything to Notion until the BA explicitly approves.

### Step 6 — Write to Notion

On BA approval, for each test case use the Notion MCP create-page tool with:

```
parent_database_id = UAT_DB_ID
properties = {
  "Test Case": [title],
  "Feature Area": [select value],
  "Steps": [text],
  "Expected Result": [text],
  "Manual Status": "Not Run",
  "Automated Status": "Not Run",
  "Notes": [text if any]
}
```

Write them one at a time. If any write fails, report which one failed and continue with the rest.

### Step 7 — Confirm

After all rows are written, tell the BA:

> "Done — [N] test cases written to the Notion UAT database under [Feature Area]. Open Notion to review. The Automated Status and Final Sign-off columns are blank — those get filled when tests run and when you sign off."

## What to leave alone

- `Automated Status` — never set this; Playwright sets it
- `Automated Run Date` — never set this
- `Final Sign-off` — never check this; the BA does it manually
- `Sign-off By` — never set this
