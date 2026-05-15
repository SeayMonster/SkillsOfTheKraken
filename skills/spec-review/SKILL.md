---
name: spec-review
description: >
  Generates an interactive HTML review page for committed design specs so the user can visually
  read, annotate per-section, and formally approve or request changes before implementation begins.
  Trigger whenever the user says "spec committed", mentions a spec file path for review, shares a
  markdown spec and asks for feedback before writing an implementation plan, or says anything like
  "review this before I dispatch agents". Even if they don't say "spec reviewer" — if a .md spec
  file has just landed and they want eyes on it, this skill applies.
---

<context>
# Spec Reviewer

Your job is to turn a committed markdown spec into a beautiful interactive HTML review page the
user can click through in their browser — then wait for them to approve or request changes.

## What the review page provides

- **Table of contents** in the sidebar with jump links
- **Per-section checkboxes** ("Looks good") + free-text comment boxes
- **Progress bar** showing how many sections have been checked off
- **Callout styling** for sections whose titles match: Goals, Risks, Open Questions, Decisions, Assumptions
- **Approve / Request Changes** buttons that copy a formatted markdown summary to the clipboard
- **Draft persistence** via localStorage — refreshing the page restores all checkboxes and comments
</context>

<task>
## Workflow

### 1. Find the spec file
Use the path the user provided. If they didn't include one, search for recently modified `.md`
files under `docs/**/specs/` in the current project.

### 2. Determine the review folder
Create `<spec-parent-dir>/review/` if it doesn't exist. For example, if the spec is at
`docs/superpowers/specs/my-spec.md`, the review folder is `docs/superpowers/specs/review/`.

### 3. Run the bundled script
```
python "<skill-dir>/scripts/generate_review.py" "<spec-path>" "<review-folder>"
```
Replace `<skill-dir>` with the absolute path to this skill's directory.  
The script will generate the HTML and auto-open it in the browser.

### 4. Tell the user
Say something like:
> "Review page is open at `<review-folder>/<spec-name>-review.html`. Check off sections as you
> read, add any notes in the comment boxes, then click **Approve** or **Request Changes** —
> both buttons copy the feedback markdown to your clipboard so you can paste it back here."
</task>

<output>
Saved as `<review-folder>/<spec-stem>-review.html`. Dark-themed, self-contained single file.
</output>
