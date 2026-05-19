---
name: ba-signoff
description: Helps a BA record manual UAT test results in Notion. BA describes what they observed; Claude finds the right Notion row, updates Manual Status and Notes, and checks Final Sign-off if the BA approves. Also supports partial updates (notes only, no sign-off yet).
trigger: Use this skill when a BA wants to record manual test results, update a UAT row, add testing notes, or sign off on a test case. Also use when a BA says "I tested X and it passed/failed" or "mark that as done".
---

# BA — Record Manual Test Results & Sign Off

<context>

## What this skill does

Finds the right test case row in the Notion UAT database, shows the BA its current state, updates Manual Status and Notes based on what the BA observed, and optionally marks Final Sign-off.

---

</context>

<task>

## Step 1 — Load config

Read `docs/ba-config.json`.

- If `notion.uat_database_id` still contains `REPLACE_WITH_`, STOP:
  > "The Notion config hasn't been set up yet. Ask your dev to fill in `docs/ba-config.json`."

Store: `UAT_DB_ID` = `notion.uat_database_id`

---

## Step 2 — Identify the test case

If the BA hasn't named a specific test case, ask:
> "Which test case are you recording results for? Give me the name or describe what you tested."

Use `notion-search` or `notion-query-data-sources` to find the matching row in the UAT database. If multiple rows match, list them and ask the BA to confirm which one.

---

## Step 3 — Show current state

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

---

## Step 4 — Collect what the BA observed

Ask:
> "What did you observe? Tell me what you did and what happened — pass, fail, or something in between."

Accept any form: "it passed", "the count was wrong", "I got an error on step 3", etc.

Determine from the BA's description:
- **Manual Status**: Pass / Fail / Not Run
- **Notes**: A clean summary of what the BA observed (rewrite their words into a clear, factual note — don't just copy-paste their message)
- **Manual Run Date**: today's date

---

## Step 5 — Sign-off decision

After collecting the observation, ask:
> "Do you want to mark Final Sign-off as complete for this test case?"

Guidance to offer if they're unsure:
- Check Final Sign-off if: you're satisfied the scenario works correctly and wouldn't block a release
- Leave it unchecked if: you found an issue, you're not done testing, or you want someone else to verify

The BA decides. Never assume.

---

## Step 6 — Update Notion

PATCH the Notion row:

```
notion-update-page(
  page_id = [found page id],
  properties = {
    "Manual Status": [Pass | Fail | Not Run],
    "Manual Run Date": [today's date],
    "Notes": [existing notes + "\n" + new observation — preserve prior notes],
    "Final Sign-off": [true | false per BA decision],
    "Sign-off By": [ask for BA's name if signing off and field is blank]
  }
)
```

Only update `Final Sign-off` and `Sign-off By` if the BA said yes to sign-off. Never clear existing notes — always append.

---

## Step 7 — Confirm

> "Updated. Manual Status = [Pass/Fail], [signed off / not signed off yet]. You can view and edit it directly in Notion any time."

---

</task>

<constraints>

## Conflict handling

If Automated Status = Pass but the BA says Fail:
- Update Manual Status = Fail as instructed
- Add a note flagging the discrepancy: "Manual observation contradicts automated result — BA flagged [what they saw]. Escalate to dev team."
- Remind the BA: "You'll want to let the dev team know so they can investigate why Playwright passed but you saw a problem."

If Automated Status = Fail but the BA wants to sign off anyway:
- Do it — the BA's sign-off is the authoritative decision
- Add a note: "BA signed off despite automated failure — see Notes for context."
- Remind the BA this will be visible to the dev team

</constraints>
