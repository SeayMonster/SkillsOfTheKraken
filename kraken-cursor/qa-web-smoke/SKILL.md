---
name: kraken-cursor-qa-web-smoke
description: >-
  Runs browser smoke tests against a staging or live app URL using Cursor
  cursor-ide-browser MCP tools. Asserts availability, console errors, interactive
  elements, and layout rendering. Use when the user asks for web smoke tests,
  kraken-cursor-qa-web-smoke, browser QA, or endpoint availability checks.
argument-hint: [target-url]
---

# kraken-cursor: qa-web-smoke

**Announce at start:** "I'm using kraken-cursor-qa-web-smoke to run browser smoke tests."

Runs browser smoke tests on the target URL provided in the arguments: `$0`.

## Browser MCP (cursor-ide-browser)

Use the **cursor-ide-browser** MCP server. Read tool schemas under the MCP descriptors before calling.

Recommended workflow:

1. `browser_navigate` — open `$0` (create or navigate the target tab).
2. `browser_lock` with `action: "lock"` — lock the tab before longer automation (after navigate).
3. `browser_snapshot` — capture accessibility tree and page structure for assertions.
4. `browser_take_screenshot` — record visual layout when needed.
5. `browser_lock` with `action: "unlock"` — release the tab when finished.

Additional tools as needed: `browser_click`, `browser_type`, `browser_fill`, `browser_scroll`, `browser_press_key`, `browser_cdp` (for console/network inspection).

Do **not** use Claude-only browser MCP servers; use cursor-ide-browser only.

## Analysis Checkpoints

1. **Console Auditing:** Scan page loading cycles for unexpected 400 or 500 status indicators or JavaScript errors in console/network streams (via `browser_cdp` or snapshot/network evidence).
2. **Interactive Elements:** Verify critical navigation structures (forms, input actions, authentication visibility) using `browser_snapshot` element refs.
3. **Visual Quality:** Record a layout snapshot with `browser_take_screenshot` to confirm rendering balance across components.

## Output

Document in standard markdown:

- Functional status (pass/fail per checkpoint)
- Response latency (approximate, from navigation to ready state)
- Any breaking layout or console errors discovered
- Attach or reference screenshot path when taken
