export const meta = {
  name: 'qa-sweep',
  description: 'Config-driven multi-agent QA sweep: discovery -> data-correctness+UI+API+visual+WPF -> selective verify -> synthesis',
  phases: [
    { title: 'Discovery',  detail: 'Crawl app, confirm DB, emit runtime manifest' },
    { title: 'Test',       detail: 'Parallel: correctness, UI render, API, visual, WPF' },
    { title: 'Verify',     detail: 'Skeptic per UI finding (numeric findings pass through)' },
    { title: 'Synthesis',  detail: 'Rank, report, baseline diff, run state' },
  ],
}

// ---- tunable budget constants (see spec §5) ----
const CORE_ESTIMATE   = 150000   // approx output tokens for the core suite
const PER_COMBO_BUDGET = 20000   // approx per exploratory filter-combo round

// args may arrive as an object or a JSON string (runtime-dependent) — normalize both.
const _A = (typeof args === 'string')
  ? (() => { try { return JSON.parse(args) } catch { return {} } })()
  : (args || {})
const cfg  = _A.config || {}
const mode = _A.mode   || 'once'   // once | dry | budget | count
const modeLimit = _A.limit || 2    // dry rounds | count | budget tokens
const nowStr = _A.now || 'unknown-date'
const depth  = (_A.depth === 'smoke') ? 'smoke' : 'full'   // smoke = fast functional loop; full = pre-handoff gate
const isSmoke = depth === 'smoke'

if (!cfg.launch || !cfg.launch.baseUrl) {
  log('ABORT: args.config.launch.baseUrl missing — pass the parsed qa-sweep.config.json as args.config.')
  return { aborted: true, reason: 'missing-config' }
}

const FINDINGS_SCHEMA = {
  type: 'object', required: ['findings'],
  properties: { findings: { type: 'array', items: {
    type: 'object', required: ['area','severity','summary','kind'],
    properties: {
      area: {type:'string'}, severity: {enum:['blocker','major','minor','cosmetic']},
      summary: {type:'string'}, repro: {type:'string'},
      kind: {enum:['numeric','ui','api','visual']}   // 'numeric' skips verify
    }
  } } }
}

phase('Discovery')

const manifest = await agent(
  `Discovery agent for a QA sweep of "${cfg.project}". The app is running at ${cfg.launch.baseUrl}.
   1. GET ${cfg.launch.baseUrl}/api/summary and record dataSource + array lengths.
   2. Confirm the DB is reachable: run sqlcmd against server ${cfg.db?.server} db ${cfg.db?.database} (integrated auth): "SELECT 1".
   3. List the pages actually present vs the configured list: ${JSON.stringify(cfg.pages)}.
   Return a manifest of what is testable right now. If /api/summary is not 200 or DB is unreachable, say so explicitly.`,
  { label: 'discovery', phase: 'Discovery', model: 'haiku', effort: 'low', schema: {
    type:'object', required:['dataSource','dbReachable','pagesPresent'],
    properties:{ dataSource:{type:'string'}, dbReachable:{type:'boolean'},
      pagesPresent:{type:'array',items:{type:'string'}}, notes:{type:'string'} } } }
)

if (!manifest || !manifest.dbReachable) {
  log(`ABORT: DB not reachable or discovery failed. ${manifest?.notes || ''}`)
  return { aborted: true, reason: 'db-unreachable-or-discovery-failed', manifest }
}
log(`Discovery ok — dataSource=${manifest.dataSource}, ${manifest.pagesPresent.length} pages (depth=${depth})`)

phase('Test')

// Data-correctness: one agent per assertion (numeric findings skip verify later)
const correctnessThunks = (cfg.assertions || []).map(a => () =>
  agent(
    `Data-correctness check "${a.name}" for ${cfg.project}.
     Run this SQL via sqlcmd (server ${cfg.db.server}, db ${cfg.db.database}, integrated auth):
       ${a.sql}
     Fetch ${cfg.launch.baseUrl}/api/summary and compute the UI value: ${a.ui}
     Compare. Return a finding with kind:"numeric", severity "blocker" if they differ, else no finding.`,
    { label: `correctness:${a.name}`, phase: 'Test', schema: FINDINGS_SCHEMA }
  ))

// Cross-page consistency
const crossThunks = (cfg.crossPage || []).map(c => () =>
  agent(
    `Cross-page consistency "${c.name}" for ${cfg.project} at ${cfg.launch.baseUrl}.
     Compare metric A (${c.a}) against metric B (${c.b}) across the two pages. They must match.
     Return a finding kind:"numeric" severity "major" if they disagree, else none.`,
    { label: `cross:${c.name}`, phase: 'Test', schema: FINDINGS_SCHEMA }
  ))

// UI render: one agent per configured group (own headless browser via webapp-testing skill)
const uiThunks = (cfg.uiGroups || cfg.pages.map(p => [p])).map(group => () =>
  agent(
    `UI render check for pages ${JSON.stringify(group)} of ${cfg.project} at ${cfg.launch.baseUrl}.
     Use the webapp-testing skill (headless Playwright). For each page: it renders, filters (${JSON.stringify(cfg.filterDimensions)}) apply,
     drawers/modals open, export fires if present, and there are ZERO console errors.${isSmoke ? '\n     If (and only if) a page is broken, capture ONE desktop screenshot into '+cfg.reportPath+'/shots/ as evidence; otherwise capture none.' : ''}
     Return findings kind:"ui" for anything broken.`,
    { label: `ui:${group.join('+')}`, phase: 'Test', model: 'haiku', effort: 'low', schema: FINDINGS_SCHEMA }
  ))

// API
const apiThunk = () => agent(
  `API check for ${cfg.project} at ${cfg.launch.baseUrl}. Hit each endpoint and assert the expected status:
   ${JSON.stringify(cfg.endpoints)}. Return findings kind:"api" for mismatches.`,
  { label: 'api', phase: 'Test', model: 'haiku', effort: 'low', schema: FINDINGS_SCHEMA })

// Visual
const visualThunk = () => agent(
  `Visual check for ${cfg.project} at ${cfg.launch.baseUrl} via headless Playwright. Render light + dark and
   mobile/tablet/desktop. Capture one screenshot per page into ${cfg.reportPath}/shots/. Return findings kind:"visual"
   for layout breakage; always return the screenshot paths in notes.`,
  { label: 'visual', phase: 'Test', model: 'haiku', effort: 'low', schema: FINDINGS_SCHEMA })

// WPF launch-smoke (only if configured)
const wpfThunks = cfg.wpf?.csproj ? [() => agent(
  `WPF launch-smoke for ${cfg.project}: run "dotnet run --project ${cfg.wpf.csproj}", confirm the window starts and the
   embedded WebView2 loads the dashboard, capture one screenshot. Do NOT attempt native control automation.
   Return a finding kind:"ui" severity "blocker" only if it fails to launch or load.`,
  { label: 'wpf-smoke', phase: 'Test', model: 'haiku', effort: 'low', schema: FINDINGS_SCHEMA })] : []

// smoke mode drops the visual screenshot matrix + WPF launch (the long-pole agents)
const coreThunks = [...correctnessThunks, ...crossThunks, ...uiThunks, apiThunk]
if (!isSmoke) coreThunks.push(visualThunk, ...wpfThunks)
const coreResults = await parallel(coreThunks)

const coreFindings = coreResults.filter(Boolean).flatMap(r => r.findings || [])
log(`Core suite done — ${coreFindings.length} raw findings`)

phase('Verify')

// Verify UI/judgment findings only; numeric/api findings are self-verifying.
const toVerify = coreFindings.filter(f => f.kind === 'ui' || f.kind === 'visual')
const passThrough = coreFindings.filter(f => f.kind === 'numeric' || f.kind === 'api')

const verified = await parallel(toVerify.map(f => () =>
  agent(
    `Skeptic: re-check this reported UI defect against the live app at ${cfg.launch.baseUrl}. Try to REFUTE it.
     Finding: ${JSON.stringify(f)}. Return {confirmed:boolean, note:string}.`,
    { label: `verify:${f.area}`, phase: 'Verify',
      schema: { type:'object', required:['confirmed'], properties:{confirmed:{type:'boolean'}, note:{type:'string'}} } }
  ).then(v => (v && v.confirmed) ? f : null)
))

const confirmed = [...passThrough, ...verified.filter(Boolean)]

phase('Synthesis')

const report = await agent(
  `Synthesis agent for the ${cfg.project} QA sweep. You are given confirmed findings:
   ${JSON.stringify(confirmed)}
   Known limitations (report verbatim, not as failures): ${JSON.stringify(cfg.knownLimitations || [])}
   Golden baseline path: ${cfg.baselinePath} (may not exist yet).
   Write a markdown report to ${cfg.reportPath}/report-latest.md with, in order:
   1. Executive gate: PASS if no blocker/major confirmed, else FAIL (one line).
   2. Findings table: severity | area | what broke | repro | verified.
   3. Data-correctness table from the numeric findings.
   4. Drift section: ${isSmoke ? 'this is a SMOKE run — write "drift/baseline skipped (smoke mode)".' : `if ${cfg.baselinePath} exists, diff current numbers/screenshots vs it; else write "baseline not yet blessed".`}
   5. Reference the screenshots under ${cfg.reportPath}/shots/.
   6. Known limitations.
   Also write ${cfg.reportPath}/state.json = {date, failures, baselineRef}. Use the date ${nowStr}.
   Return {gate:"PASS"|"FAIL", failures:number, reportPath:string}.`,
  { label: 'synthesis', phase: 'Synthesis',
    schema: { type:'object', required:['gate','failures','reportPath'],
      properties:{ gate:{enum:['PASS','FAIL']}, failures:{type:'number'}, reportPath:{type:'string'} } } }
)

// ---- Exploratory loop (mode-driven) — wraps ONLY exploration, core already ran ----
const explored = []
if (mode !== 'once') {
  const startSpent = budget.spent()
  let dry = 0, rounds = 0
  const combos = (cfg.filterDimensions || []).length ? cfg.filterDimensions : ['default']
  while (true) {
    if (mode === 'count'  && rounds >= modeLimit) break
    if (mode === 'budget' && (budget.spent() - startSpent) >= modeLimit) break
    if (mode === 'dry'    && dry >= modeLimit) break
    const r = await agent(
      `Exploratory round ${rounds+1} for ${cfg.project} at ${cfg.launch.baseUrl}. Pick an untried combination of
       filters (${JSON.stringify(combos)}) and drive the UI; report only NEW distinct defects not already in:
       ${JSON.stringify(explored)}. Return findings (kind:"ui").`,
      { label: `explore:${rounds+1}`, phase: 'Verify', model: 'haiku', effort: 'low', schema: FINDINGS_SCHEMA })
    const fresh = (r && r.findings) || []
    if (!fresh.length) dry++; else { dry = 0; explored.push(...fresh) }
    rounds++
    if (rounds > 50) break   // hard backstop
  }
  log(`Exploration done — ${rounds} rounds, ${explored.length} extra findings`)
}

return { gate: report?.gate, failures: report?.failures, reportPath: report?.reportPath, explored: explored.length, mode }
