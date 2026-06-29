export const meta = {
  name: 'qa-uat',
  description: 'Multi-agent UAT: coordinate → parallel db-assert + batched web-ui → finalize',
  phases: [
    { title: 'Coordinate', detail: 'Fetch doc, classify cases, init uat-results.json, launch watcher' },
    { title: 'ExecuteDbAssert', detail: 'Parallel agents for db-assert cases (batch up to 4)' },
    { title: 'ExecuteWebUi', detail: 'Sequential/batched web-ui and mixed cases (max 2 parallel)' },
    { title: 'Finalize', detail: 'Set completed_at and print summary' },
  ],
}

const COORDINATE_SCHEMA = {
  type: 'object',
  required: ['clientName', 'qaBotsRepo', 'resultsPath', 'dbAssertCases', 'webUiCases', 'mixedCases'],
  properties: {
    clientName: { type: 'string' },
    qaBotsRepo: { type: 'string' },
    resultsPath: { type: 'string' },
    uatBaseUrl: { type: 'string' },
    uatDbServer: { type: 'string' },
    uatDbName: { type: 'string' },
    dbAssertCases: { type: 'array' },
    webUiCases: { type: 'array' },
    mixedCases: { type: 'array' },
  },
}

const CASE_RESULT_SCHEMA = {
  type: 'object',
  required: ['id', 'status', 'issues'],
  properties: {
    id: { type: 'string' },
    status: { type: 'string' },
    issues: { type: 'array' },
  },
}

const clientRepoRoot = (args && args.clientRepoRoot) || process.cwd()

phase('Coordinate')

const coordinated = await agent(
  `You are the Coordinate agent for qa-uat.

Client repo root: ${clientRepoRoot}

Steps 1–5 from qa-uat SKILL.md:
1. Pre-flight (qa-bots-path, qa-config with uat_doc_id, epic_project_map, uat_base_url, uat_db_*).
2. Fetch and parse UAT doc (Google Drive MCP or local fallback).
3. Filter by epic_project_map, classify (web-ui, db-assert, mixed, not-done).
4. Write uat-results.json.
5. Launch watcher + dashboard.

Return JSON:
- clientName, qaBotsRepo, resultsPath (full path to uat-results.json)
- uatBaseUrl, uatDbServer, uatDbName
- dbAssertCases: pending cases with classification db-assert (include id, action_steps, expected_result, project)
- webUiCases: pending web-ui only
- mixedCases: pending mixed`,
  { phase: 'Coordinate', schema: COORDINATE_SCHEMA, label: 'coordinate' }
)

if (!coordinated) throw new Error('Coordinate phase failed.')

log(`db-assert: ${coordinated.dbAssertCases.length} | web-ui: ${coordinated.webUiCases.length} | mixed: ${coordinated.mixedCases.length}`)

// --- Phase 2a: db-assert (parallel, batch 4) ---

phase('ExecuteDbAssert')

const dbCases = coordinated.dbAssertCases || []
for (let i = 0; i < dbCases.length; i += 4) {
  const batch = dbCases.slice(i, i + 4)
  await parallel(
    batch.map(tc => () =>
      agent(
        `You are the db-assert agent for UAT case "${tc.id}".

Results file: ${coordinated.resultsPath}
DB: ${coordinated.uatDbServer} / ${coordinated.uatDbName}
Expected: ${tc.expected_result}
Action context: ${tc.action_steps}

1. Set case status "running" in uat-results.json.
2. Derive SQL assertions from expected_result. Use POGSplit Epic 4 template if applicable.
3. Run sqlcmd for each query. Collect issues.
4. Resolve status (error → fail, else pass). Update uat-results.json.

Return: { id: "${tc.id}", status, issues }.`,
        { phase: 'ExecuteDbAssert', schema: CASE_RESULT_SCHEMA, label: `db-${tc.id}` }
      )
    )
  )
}

// --- Phase 2b: web-ui (sequential — browser state) ---

phase('ExecuteWebUi')

for (const tc of coordinated.webUiCases || []) {
  await agent(
    `You are the web-ui agent for UAT case "${tc.id}".

Results file: ${coordinated.resultsPath}
Base URL: ${coordinated.uatBaseUrl}
Action steps: ${tc.action_steps}
Expected: ${tc.expected_result}

Use Claude-in-Chrome MCP. Set running, execute steps, assert, update uat-results.json.
Return: { id: "${tc.id}", status, issues }.`,
    { phase: 'ExecuteWebUi', schema: CASE_RESULT_SCHEMA, label: `web-${tc.id}` }
  )
}

// mixed: sequential web then db per case
for (const tc of coordinated.mixedCases || []) {
  await agent(
    `You are the mixed runner for UAT case "${tc.id}".

Results file: ${coordinated.resultsPath}
Run web-ui first (Chrome MCP at ${coordinated.uatBaseUrl}), then db-assert (sqlcmd ${coordinated.uatDbServer}/${coordinated.uatDbName}).
Concatenate issues. Update uat-results.json.
Return: { id: "${tc.id}", status, issues }.`,
    { phase: 'ExecuteWebUi', schema: CASE_RESULT_SCHEMA, label: `mixed-${tc.id}` }
  )
}

// --- Phase 3: Finalize ---

phase('Finalize')

await agent(
  `Finalize qa-uat for ${coordinated.clientName}. Set completed_at in ${coordinated.resultsPath}. Print pass/fail/not-done summary.`,
  { phase: 'Finalize', label: 'finalize' }
)
