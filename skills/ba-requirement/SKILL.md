---
name: ba-requirement
description: Helps a BA turn a conversation, email thread, or verbal description into a structured requirement or user story, then writes the finished requirement to the Notion Requirements database.
trigger: Use this skill when a BA asks to write, draft, capture, or structure a requirement, user story, or feature request. Also use when a BA pastes an email or meeting notes and says "turn this into a requirement".
---

# BA — Write a Requirement

<context>

## What this skill does

Takes a BA's raw input (description, email, meeting notes, bullet points) and turns it into a structured requirement with acceptance criteria, then writes it to the Notion Requirements database after BA approval.

---

</context>

<task>

## Step 1 — Load config

Read `docs/ba-config.json`.

- If `notion.requirements_database_id` still contains `REPLACE_WITH_`, STOP and tell the BA:
  > "The Notion config hasn't been filled in yet. Ask your dev to open `docs/ba-config.json` and add the Notion database IDs."
  Then exit.

Store: `REQ_DB_ID` = `notion.requirements_database_id`

---

## Step 2 — Gather input

If the BA hasn't provided raw input yet, ask:
> "Tell me what this requirement is about — paste an email, describe it in plain language, or give me bullet points. Whatever you have is fine."

Accept any form: prose, bullets, email thread, voice-to-text transcript.

---

## Step 3 — Clarify if needed

Before drafting, identify any gaps. Ask ONE clarifying question at a time if any of these are unknown:
- Who is the user/role this is for?
- What problem does it solve?
- What does success look like?

Only ask if genuinely needed — don't interrogate the BA for information you can reasonably infer.

---

## Step 4 — Draft the requirement

Structure the requirement as follows:

```
Title: [One-line description]
Feature: [POGSplit | LifecycleManagement | FloorPlanning | SpacePlanning | Other]
Priority: [High | Medium | Low] — ask the BA if not obvious

User Story:
As a [role], I want [goal], so that [business value].

Acceptance Criteria:
- [ ] Criterion 1 — specific, observable, testable
- [ ] Criterion 2
- [ ] Criterion 3

Notes:
[Open questions, dependencies, out-of-scope items]
```

Rules for acceptance criteria:
- Each criterion must be independently testable
- Write what the system does, not how it does it
- Avoid vague words like "quickly", "easily", "properly" — use observable outcomes instead
- Aim for 3–6 criteria. More than 8 usually means the requirement needs splitting.

Present the draft to the BA.

---

## Step 5 — BA review loop

Ask:
> "Does this capture it correctly? Let me know what to add, change, or remove."

Apply feedback and re-present. Repeat until approved.

---

## Step 6 — Write to Notion

On BA approval:

```
notion-create-pages(
  parent_database_id = REQ_DB_ID,
  properties = {
    "Title": [title],
    "Feature": [select],
    "Priority": [select],
    "User Story": [text],
    "Acceptance Criteria": [text — formatted as checklist],
    "Notes": [text],
    "Status": "Draft"
  }
)
```

---

## Step 7 — Confirm

> "Requirement written to Notion. It's in Draft status — update it to In Review when you're ready to share it with the dev team."

---

</task>

<constraints>

## Tips for good requirements

- If the BA brings a requirement that's actually two features, split it and handle them separately
- "The system should be fast" is not a requirement — push for an observable outcome
- Acceptance criteria drive UAT test cases — well-written criteria make `/ba-generate-uat` much faster

</constraints>
