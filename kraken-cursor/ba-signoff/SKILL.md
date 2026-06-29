---
name: kraken-cursor-ba-signoff
description: >-
  Helps a BA record manual UAT test results in Notion. Finds the right Notion row, updates
  Manual Status and Notes, and checks Final Sign-off if the BA approves. Also supports partial
  updates (notes only, no sign-off yet). Use when a BA wants to record manual test results,
  update a UAT row, add testing notes, or sign off — e.g. "I tested X and it passed/failed"
  or "mark that as done". Invoke with Use kraken-cursor-ba-signoff.
---

# kraken-cursor: ba-signoff

**Announce at start:** "I'm using kraken-cursor-ba-signoff to record UAT results."

Finds the right test case row in the Notion UAT database, shows the BA its current state, updates Manual Status and Notes based on what the BA observed, and optionally marks Final Sign-off.

## Pre-flight

1. Resolve `{repoRoot}` = client repo root.
2. Read `{repoRoot}/docs/ba-config.json`.
   - If `notion.uat_database_id` still contains `REPLACE_WITH_`, STOP:
     > "The Notion config hasn't been set up yet. Ask your dev to run **Use kraken-cursor-dev-notion-setup** or fill in `{repoRoot}/docs/ba-config.json`."
   - Then exit.
3. Store: `UAT_DB_ID` = `notion.uat_database_id`
4. Use the **plugin-notion-workspace-notion** MCP server for search, query, fetch, and update. Read tool schemas before calling `CallMcpTool`. If authentication fails, call `mcp_auth` once, then retry.

## Steps

### Step 1 — Identify the test case

If the BA hasn't named a specific test case, ask:

> "Which test case are you recording results for? Give me the name or describe what you tested."

Use Notion MCP search or database-query tools to find the matching row in the UAT database. If multiple rows match, list them and ask the BA to confirm which one.

### Step 2 — Show current state

Fetch the full row and display a summary:

```
Test Case: [name]
Feature Area: [area]
Automated Status: [Pass | Fail | Not Run]
Manual Status: [current value]
Final Sign-off: [checked | unchecked]
Notes: [current notes if any]
```

This gives the BA full context before making any changes.

### Step 3 — Collect what the BA observed

Ask:

> "What did you observe? Tell me what you did and what happened — pass, fail, or something in between."

Accept any form: "it passed", "the count was wrong", "I got an error on step 3", etc.

Determine from the BA's description:

- **Manual Status**: Pass / Fail / Not Run
- **Notes**: A clean summary of what the BA observed (rewrite their words into a clear, factual note — don't just copy-paste their message)
- **Manual Run Date**: today's date

### Step 4 — Sign-off decision

After collecting the observation, ask:

> "Do you want to mark Final Sign-off as complete for this test case?"

Guidance to offer if they're unsure:

- Check Final Sign-off if: you're satisfied the scenario works correctly and wouldn't block a release
- Leave it unchecked if: you found an issue, you're not done testing, or you want someone else to verify

The BA decides. Never assume.

### Step 5 — Update Notion

Use the Notion MCP update-page tool with:

```
page_id = [found page id]
properties = {
  "Manual Status": [Pass | Fail | Not Run],
  "Manual Run Date": [today's date],
  "Notes": [existing notes + "\n" + new observation — preserve prior notes],
  "Final Sign-off": [true | false per BA decision],
  "Sign-off By": [ask for BA's name if signing off and field is blank]
}
```

Only update `Final Sign-off` and `Sign-off By` if the BA said yes to sign-off. Never clear existing notes — always append.

### Step 6 — Confirm

> "Updated. Manual Status = [Pass/Fail], [signed off / not signed off yet]. You can view and edit it directly in Notion any time."

## Conflict handling

If Automated Status = Pass but the BA says Fail:

- Update Manual Status = Fail as instructed
- Add a note flagging the discrepancy: "Manual observation contradicts automated result — BA flagged [what they saw]. Escalate to dev team."
- Remind the BA: "You'll want to let the dev team know so they can investigate why Playwright passed but you saw a problem."

If Automated Status = Fail but the BA wants to sign off anyway:

- Do it — the BA's sign-off is the authoritative decision
- Add a note: "BA signed off despite automated failure — see Notes for context."
- Remind the BA this will be visible to the dev team
