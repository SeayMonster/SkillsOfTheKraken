---
name: kraken-cursor-qa-process-flow
description: >-
  Opens the QA Bot process flow guide in the browser. Shows setup steps,
  per-client workflow, commands reference, and edge case handling. Use when the
  user asks for QA process flow, kraken-cursor-qa-process-flow, QA workflow
  overview, or how QA bots setup works in Cursor.
---

# kraken-cursor: qa-process-flow

**Announce at start:** "I'm using kraken-cursor-qa-process-flow to open the QA process flow guide."

Opens the QA process flow HTML guide in the Cursor browser.

## Steps

1. Resolve the guide path: `{SKILL_DIR}/process-flow.html` (the directory containing this skill's `SKILL.md`).

2. If `process-flow.html` does not exist at that path: "Could not locate process-flow.html in the kraken-cursor-qa-process-flow skill folder." Stop.

3. Open the guide using **cursor-ide-browser** MCP:
   - Read tool schemas under the MCP descriptors before calling.
   - Convert the absolute path to a `file:///` URL (forward slashes, URL-encoded spaces).
   - Call `browser_navigate` with that URL.
   - Optionally call `browser_snapshot` to confirm the page loaded.

Do **not** search hardcoded clone paths or use `Start-Process` — the HTML ships with this skill at `{SKILL_DIR}/process-flow.html`.
