---
name: kraken-cursor-html-likeness
description: >-
  Compare a reference HTML dashboard against a target HTML and produce a gap punch list.
  Use when a business user updates the reference and you need to port changes to the EXE/served
  version. Trigger: "likeness", "port changes from reference", "sync dashboard",
  "what changed in the HTML", or kraken-cursor-html-likeness.
---

# kraken-cursor: html-likeness

**Announce at start:** "I'm using kraken-cursor-html-likeness to compare reference and target HTML."

Business users maintain a reference HTML dashboard. A separate target HTML is served inside a WPF exe via WebView2. When the reference changes, this skill identifies every gap so they can be ported without missing anything.

## Pre-flight

1. Resolve `repoRoot` = client repo root (directory containing `_package-request.json`, a `.sln`, or the project the user names).
2. Obtain **reference** and **target** HTML paths from the user when possible.

If paths are not provided, search `{repoRoot}` for candidate pairs:

- Look under `**/wwwroot/*.html` or paths the user mentions (e.g. `ReportingDashboard.html`).
- **Reference** = business user's canonical / design copy (often the file they edited).
- **Target** = version served in the WPF exe (may be the same path in some repos — confirm with the user which file is authoritative for each role).

Never hardcode user-specific absolute paths. Stop and ask if you cannot resolve both files.

## Step 1 — Resolve file paths

If the user provides both paths explicitly, use them.

Otherwise use search results from pre-flight and confirm the pair with the user before continuing.

## Step 2 — Spawn parallel investigator agents

Launch two **Task** subagents with `subagent_type: "cavecrew-investigator"` in parallel — one per file. Each agent must return:

### Per-file audit checklist

For each HTML file, extract and return verbatim:

1. **Header / branding** — logo, title, eyebrow text, badge text, top-right buttons (exact text/IDs)
2. **Tab labels** — all tab names and their `data-tab` values
3. **User Preferences panel** — every preference row: label + options (e.g. "Appearance: Light / Dark")
4. **Filter mechanism** — popup filter fields, top-of-page filter fields, what columns are filterable
5. **Overview KPI cards** — card titles and data fields shown
6. **Charts** — chart titles, types, data sources
7. **CSS variables defined** — full list from `:root` and `html[data-theme="dark"]`
8. **Key JS functions** — list of top-level function names
9. **Data shape** — what fields does the page expect from the API / injected data (`CELLS`, `ACCOUNTS`, etc.)
10. **Export options** — what export buttons exist and what format they produce
11. **Interactive component positioning** — for every dropdown, panel, or modal: note the CSS positioning strategy (`position:absolute` anchored to a relative wrapper vs `position:fixed`), the DOM structure (panel inside its trigger wrapper vs body-level), and z-index stack. Flag mismatches as structural gaps — they won't appear in a content diff but cause visible alignment bugs at runtime.

Return as a structured list with section headers and line numbers.

## Step 3 — Diff and produce gap report

Compare the two audit reports. For each section, output a table:

```
| Section           | Reference                        | Target                          | Gap |
|-------------------|----------------------------------|---------------------------------|-----|
| Header eyebrow    | "PogCloud Analytics"             | "Hershey"                       | ✓   |
| Pref: Filtering   | Pop-up / Top of page             | Missing                         | ✗   |
| Tab: Details      | "Planogram + Product Details"    | Present                         | ✓   |
```

Gap legend:

- ✓ = matches or intentionally different (note why)
- ✗ = missing from target — must be ported
- ~ = partially present — needs update

## Step 4 — Port list

After the table, output a prioritized action list:

```
## Gaps to port (✗ items only)

### HIGH — visible to user
1. [Section] [what's missing] — add to [file:line]

### MEDIUM — functional but incomplete
...

### LOW — cosmetic / copy
...
```

For each gap, include the exact reference file line numbers so the implementer can read them directly.

## Step 5 — Offer to apply

Ask: "Apply all gaps now, or review first?"

If user says apply: for each gap, make the targeted edit to the **target** file. One edit per gap. Do not rewrite surrounding code.

## Rules

- Never modify the reference file
- Never guess — if a section is ambiguous, flag it with `?` in the Gap column
- If the reference has something that should NOT be in the target (e.g. server-specific code), mark it `N/A` with a note
- After porting, re-run Step 2–3 to confirm gap count is 0

## Related

- Claude Code equivalent: Use kraken html-likeness (source skill `skills/html-likeness/`)
