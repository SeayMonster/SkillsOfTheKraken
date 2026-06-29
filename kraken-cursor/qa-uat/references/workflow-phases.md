# Workflow phases — kraken-cursor-qa-uat

Parent agent: execute phases in order.

State file: `QA_BOTS_REPO\clients\<name>\.qa-run\uat-results.json` — rewrite full file after each case update.

---

## Phase 1: Coordinate

**Parent executes** Steps 1–5 from SKILL.md (fetch doc, classify, init uat-results.json, launch watcher).

Return case lists:
- `dbAssertCases[]` — pending, classification `db-assert`
- `webUiCases[]` — pending, classification `web-ui`
- `mixedCases[]` — pending, classification `mixed`

---

## Phase 2a: Execute db-assert (PARALLEL — up to 4 Tasks per message)

```
You are the db-assert agent for UAT case "{testCaseId}".

Results file: {resultsPath}
Server: {uatDbServer}  Database: {uatDbName}
Action steps: {actionSteps}
Expected result: {expectedResult}

1. Set status "running" in uat-results.json.
2. Derive SQL from expected_result (POGSplit Epic 4 template if applicable).
3. Run sqlcmd. Collect issues.
4. status: error → fail; else pass. Write uat-results.json.

Return: { id, status, issues }.
```

Launch all db-assert Tasks in batches of 4.

---

## Phase 2b: Execute web-ui (SEQUENTIAL — one Task at a time)

Browser state is shared — do **not** parallelize web-ui beyond 1–2 cases with isolated profiles.

```
You are the web-ui agent for UAT case "{testCaseId}".

Use plugin-playwright-playwright MCP or cursor-ide-browser.
Base URL: {uatBaseUrl}
Follow action_steps, assert expected_result, check console/network.

Update uat-results.json. Return: { id, status, issues }.
```

Run each web-ui case sequentially.

---

## Phase 2c: Execute mixed (SEQUENTIAL)

For each mixed case: web-ui runner first, then db-assert. One Task per case.

---

## Phase 3: Finalize

Set `completed_at`, print pass/fail/not-done summary and dashboard path.
