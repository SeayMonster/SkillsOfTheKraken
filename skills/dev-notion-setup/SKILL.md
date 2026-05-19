---
name: dev-notion-setup
description: >
  One-time dev setup for a client's Notion workspace. Creates UAT Test Cases and Requirements
  databases under a named Notion page, then writes all IDs to docs/ba-config.json and commits.
  Use when setting up a new client project, or when ba-config.json still has REPLACE_WITH_*
  placeholders. Triggered by "/dev-notion-setup", "set up notion", "create notion databases",
  or "notion setup".
---

<context>
This skill wires up the Notion infrastructure for a client project. It is run once by a developer
— not BAs. After it completes, every BA who clones the repo has all Notion IDs automatically via
ba-config.json.

Config file: `docs/ba-config.json` (relative to the repo root).

UAT Test Cases database schema (11 properties):
| Property           | Notion Type | Notes                                    |
|--------------------|-------------|------------------------------------------|
| Test Case          | title       | Name of the scenario (required)          |
| Feature Area       | select      | e.g. POGSplit, LifecycleManagement       |
| Steps              | rich_text   | BA-authored manual steps                 |
| Expected Result    | rich_text   | What success looks like                  |
| Automated Status   | select      | Pass / Fail / Not Run                    |
| Automated Run Date | date        | Timestamp of last Playwright run         |
| Manual Status      | select      | Pass / Fail / Not Run                    |
| Manual Run Date    | date        | When BA manually tested                  |
| Notes              | rich_text   | Observations, screenshots, bug links     |
| Final Sign-off     | checkbox    | BA's authoritative pass/fail decision    |
| Sign-off By        | rich_text   | Which BA signed off                      |

Requirements database schema (5 properties):
| Property            | Notion Type | Notes                                   |
|---------------------|-------------|-----------------------------------------|
| Requirement         | title       | Short requirement title (required)      |
| Description         | rich_text   | Full requirement detail                 |
| Acceptance Criteria | rich_text   | Conditions that define done             |
| Status              | select      | Draft / Reviewed / Approved             |
| Source              | rich_text   | Origin (email, meeting, ticket ref)     |
</context>

<task>
## Step 1 — Read current config

Read `docs/ba-config.json`. Identify which IDs are still placeholders (contain `REPLACE_WITH_`).
Show the dev a summary:

```
Current ba-config.json status:
  ✅ academy_page_id       — already set
  ❌ requirements_database_id — needs setup
  ❌ functional_specs_page_id — needs setup
  ❌ sdd_page_id            — needs setup
```

Only proceed with items that are missing. Skip anything already configured.

---

## Step 2 — Confirm the Notion page

If `academy_page_id` is already set, skip this step and use the existing ID.

Otherwise ask: **"What is the name of the Notion page for this client? (e.g. 'Academy / BlueYonder')"**

Use the `notion-search` MCP tool to find the page by name. Show the results and ask the dev to confirm which one is correct. Use the confirmed page ID going forward.

---

## Step 3 — Create missing databases

For each database whose ID is a placeholder, create it under the academy page using the Notion MCP.

### UAT Test Cases database

Use `notion-create-database` with parent = academy page ID and these properties:

```json
{
  "Test Case":          { "title": {} },
  "Feature Area":       { "select": { "options": [{"name":"POGSplit"},{"name":"LifecycleManagement"},{"name":"General"}] } },
  "Steps":              { "rich_text": {} },
  "Expected Result":    { "rich_text": {} },
  "Automated Status":   { "select": { "options": [{"name":"Not Run"},{"name":"Pass"},{"name":"Fail"}] } },
  "Automated Run Date": { "date": {} },
  "Manual Status":      { "select": { "options": [{"name":"Not Run"},{"name":"Pass"},{"name":"Fail"}] } },
  "Manual Run Date":    { "date": {} },
  "Notes":              { "rich_text": {} },
  "Final Sign-off":     { "checkbox": {} },
  "Sign-off By":        { "rich_text": {} }
}
```

Save the returned database ID as `uat_database_id`.

### Requirements database

Use `notion-create-database` with parent = academy page ID and these properties:

```json
{
  "Requirement":            { "title": {} },
  "Description":            { "rich_text": {} },
  "Acceptance Criteria":    { "rich_text": {} },
  "Status":                 { "select": { "options": [{"name":"Draft"},{"name":"Reviewed"},{"name":"Approved"}] } },
  "Source":                 { "rich_text": {} }
}
```

Save the returned database ID as `requirements_database_id`.

---

## Step 4 — Find Functional Specs and SDD pages

If `functional_specs_page_id` or `sdd_page_id` are still placeholders:

Use `notion-search` to find pages named "Functional Specs" and "SDD" (or similar) that are children
of the academy page. Show candidates to the dev and confirm. If not found, tell the dev:
> "Could not find a Functional Specs or SDD page under the Academy page. Create those pages in Notion
> first, then re-run /dev-notion-setup to pick them up. Skipping for now."

---

## Step 5 — Update ba-config.json

Write all newly found/created IDs into `docs/ba-config.json`. Only update keys that were placeholders
— do not overwrite keys that were already set. Preserve all existing structure and comments.

Example of what gets updated:
```json
{
  "notion": {
    "academy_page_id": "<existing or newly found>",
    "uat_database_id": "<newly created>",
    "requirements_database_id": "<newly created>",
    "functional_specs_page_id": "<found or REPLACE_WITH_... if not found>",
    "sdd_page_id": "<found or REPLACE_WITH_... if not found>"
  }
}
```

---

## Step 6 — Commit

Stage and commit `docs/ba-config.json`:

```
git add docs/ba-config.json
git commit -m "chore: populate Notion IDs via /dev-notion-setup

UAT Test Cases DB, Requirements DB, and page IDs written to ba-config.json.
BAs cloning the repo will have all IDs automatically."
```

---

## Step 7 — Report

Tell the dev:

```
✅ Notion setup complete.

  academy_page_id:          <id>
  uat_database_id:          <id>
  requirements_database_id: <id>
  functional_specs_page_id: <id or "not found — create manually">
  sdd_page_id:              <id or "not found — create manually">

ba-config.json committed. BAs can now clone and run /ba-workflow immediately.
```
</task>
