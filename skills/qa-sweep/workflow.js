export const meta = {
  name: 'qa-sweep',
  description: 'Config-driven multi-agent QA sweep: discovery -> data-correctness+UI+API+visual+WPF -> selective verify -> synthesis',
  phases: [
    { title: 'Discovery',  detail: 'Confirm DB + cache, crawl web app if present, emit runtime manifest' },
    { title: 'Test',       detail: 'Parallel: SQL correctness (cache vs source), UI render, API, visual, WPF' },
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

// A web app exposes an HTTP baseUrl (fetch /api, drive pages with Playwright). A WPF-only app
// (baseUrl omitted / launch.mode === 'wpf') has NO HTTP server — its WebView2 serves /api via a
// virtual-host fetch shim no external tool can reach — so the HTTP UI/API/visual/exploratory
// agents are skipped and correctness runs SQL-side only (cache table counts vs live source).
const hasWeb = !!(cfg.launch && cfg.launch.baseUrl)
const src    = cfg.db || {}
const cache  = cfg.cacheDb || cfg.db || {}   // cache DB the app reads; falls back to db if unset

if (!hasWeb && !(cfg.assertions || []).length) {
  log('ABORT: no launch.baseUrl (web) and no assertions (SQL) — nothing to test. Pass a parsed qa-sweep.config.json as args.config.')
  return { aborted: true, reason: 'missing-config' }
}
if (!hasWeb && !src.server) {
  log('ABORT: WPF/SQL-only mode needs cfg.db.server (and cfg.cacheDb) to run correctness assertions.')
  return { aborted: true, reason: 'missing-db' }
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

const discoveryPrompt = hasWeb
  ? `Discovery agent for a QA sweep of "${cfg.project}" (WEB app at ${cfg.launch.baseUrl}).
     1. GET ${cfg.launch.baseUrl}/api/summary and record dataSource + array lengths.
     2. Confirm the source DB is reachable: sqlcmd -S "${src.server}" -d ${src.database} -E -C -Q "SELECT 1".
     3. Confirm the cache DB is reachable and its rpt_* tables exist: sqlcmd -S "${cache.server}" -d ${cache.database} -E -C -Q "SELECT name FROM sys.tables WHERE name LIKE 'rpt_%'".
     4. List the pages actually present vs the configured list: ${JSON.stringify(cfg.pages)}.
     Return a manifest of what is testable right now. If /api/summary is not 200 or a DB is unreachable, say so explicitly.`
  : `Discovery agent for a QA sweep of "${cfg.project}" (WPF-ONLY app — there is NO HTTP server; do NOT try to fetch a URL).
     1. Confirm the source DB is reachable: sqlcmd -S "${src.server}" -d ${src.database} -E -C -Q "SELECT 1".
     2. Confirm the cache DB is reachable and list its rpt_* tables: sqlcmd -S "${cache.server}" -d ${cache.database} -E -C -Q "SELECT name FROM sys.tables WHERE name LIKE 'rpt_%' ORDER BY name".
     3. Confirm the WPF project builds/exists: ${cfg.wpf && cfg.wpf.csproj ? cfg.wpf.csproj : '(no wpf.csproj configured)'}.
     Return a manifest. Set dataSource:"cache". If either DB is unreachable or the rpt_* tables are missing, say so explicitly in notes and set dbReachable:false.`

const manifest = await agent(discoveryPrompt,
  { label: 'discovery', phase: 'Discovery', model: 'haiku', effort: 'low', schema: {
    type:'object', required:['dataSource','dbReachable','pagesPresent'],
    properties:{ dataSource:{type:'string'}, dbReachable:{type:'boolean'},
      pagesPresent:{type:'array',items:{type:'string'}}, notes:{type:'string'} } } }
)

if (!manifest || !manifest.dbReachable) {
  log(`ABORT: DB not reachable or discovery failed. ${manifest?.notes || ''}`)
  return { aborted: true, reason: 'db-unreachable-or-discovery-failed', manifest }
}
log(`Discovery ok — dataSource=${manifest.dataSource}, web=${hasWeb}, ${manifest.pagesPresent.length} pages (depth=${depth})`)

phase('Test')

// ---- Data-correctness: one agent per assertion (numeric findings skip verify later) ----
// Two assertion shapes are supported:
//   SQL-only (WPF or web): { cacheSql, sourceSql?, rule, expect? }
//     rule "cacheEqualsSource" — run cacheSql vs sourceSql, fail if they differ.
//     rule "expectValue"       — run cacheSql, fail if it != expect.
//   Legacy web (needs baseUrl): { sql, ui } — SQL count vs a value computed from /api/summary.
const correctnessThunks = (cfg.assertions || []).map(a => () => {
  const sev = a.severity || 'blocker'
  if (a.cacheSql) {
    const rule = a.rule || (a.sourceSql ? 'cacheEqualsSource' : 'expectValue')
    const body = rule === 'expectValue'
      ? `Run the cache query via sqlcmd -S "${cache.server}" -d ${cache.database} -E -C:
           ${a.cacheSql}
         The result MUST equal ${a.expect}. Report a finding if it does not.`
      : `Run BOTH queries via sqlcmd (integrated auth, -E -C) on server "${cache.server}":
           CACHE : ${a.cacheSql}
           SOURCE: ${a.sourceSql}
         The two counts MUST be equal. Report a finding if the cache count differs from the source count
         (a cache count HIGHER than source is the classic "modeled/mock data instead of real cache" bug).`
    return agent(
      `Data-correctness check "${a.name}" for ${cfg.project} (backs UI badge ${a.tab || '?'}).
       ${body}
       Context: ${a.note || ''}
       Return a finding kind:"numeric", severity "${sev}" if the check fails; otherwise return no finding.`,
      { label: `correctness:${a.name}`, phase: 'Test', schema: FINDINGS_SCHEMA }
    )
  }
  // legacy web assertion
  return agent(
    `Data-correctness check "${a.name}" for ${cfg.project}.
     Run this SQL via sqlcmd (server ${src.server}, db ${src.database}, integrated auth):
       ${a.sql}
     Fetch ${cfg.launch.baseUrl}/api/summary and compute the UI value: ${a.ui}
     Compare. Return a finding kind:"numeric", severity "${sev}" if they differ, else no finding.`,
    { label: `correctness:${a.name}`, phase: 'Test', schema: FINDINGS_SCHEMA }
  )
})

// ---- Cross-page consistency (web only — needs live pages to compare) ----
const crossThunks = (hasWeb ? (cfg.crossPage || []) : []).map(c => () =>
  agent(
    `Cross-page consistency "${c.name}" for ${cfg.project} at ${cfg.launch.baseUrl}.
     Compare metric A (${c.a}) against metric B (${c.b}) across the two pages. They must match.
     Return a finding kind:"numeric" severity "major" if they disagree, else none.`,
    { label: `cross:${c.name}`, phase: 'Test', schema: FINDINGS_SCHEMA }
  ))

// ---- UI render (web only) ----
const uiThunks = (hasWeb ? (cfg.uiGroups || cfg.pages.map(p => [p])) : []).map(group => () =>
  agent(
    `UI render check for pages ${JSON.stringify(group)} of ${cfg.project} at ${cfg.launch.baseUrl}.
     Use the webapp-testing skill (headless Playwright). For each page: it renders, filters (${JSON.stringify(cfg.filterDimensions)}) apply,
     drawers/modals open, export fires if present, and there are ZERO console errors.${isSmoke ? '\n     If (and only if) a page is broken, capture ONE desktop screenshot into '+cfg.reportPath+'/shots/ as evidence; otherwise capture none.' : ''}
     Return findings kind:"ui" for anything broken.`,
    { label: `ui:${group.join('+')}`, phase: 'Test', model: 'haiku', effort: 'low', schema: FINDINGS_SCHEMA }
  ))

// ---- API (web only) ----
const apiThunks = (hasWeb && (cfg.endpoints || []).length) ? [() => agent(
  `API check for ${cfg.project} at ${cfg.launch.baseUrl}. Hit each endpoint and assert the expected status:
   ${JSON.stringify(cfg.endpoints)}. Return findings kind:"api" for mismatches.`,
  { label: 'api', phase: 'Test', model: 'haiku', effort: 'low', schema: FINDINGS_SCHEMA })] : []

// ---- Visual (web only) ----
const visualThunks = (hasWeb && !isSmoke) ? [() => agent(
  `Visual check for ${cfg.project} at ${cfg.launch.baseUrl} via headless Playwright. Render light + dark and
   mobile/tablet/desktop. Capture one screenshot per page into ${cfg.reportPath}/shots/. Return findings kind:"visual"
   for layout breakage; always return the screenshot paths in notes.`,
  { label: 'visual', phase: 'Test', model: 'haiku', effort: 'low', schema: FINDINGS_SCHEMA })] : []

// ---- WPF launch-smoke (if configured; runs in full depth regardless of web/wpf) ----
const wpfThunks = (cfg.wpf?.csproj && !isSmoke) ? [() => agent(
  `WPF launch-smoke for ${cfg.project}: run "dotnet run --project ${cfg.wpf.csproj}", confirm the window starts and the
   embedded WebView2 loads the dashboard, capture one screenshot. Do NOT attempt native control automation.
   Return a finding kind:"ui" severity "blocker" only if it fails to launch or load.`,
  { label: 'wpf-smoke', phase: 'Test', model: 'haiku', effort: 'low', schema: FINDINGS_SCHEMA })] : []

// smoke mode drops the visual screenshot matrix + WPF launch (the long-pole agents)
const coreThunks = [...correctnessThunks, ...crossThunks, ...uiThunks, ...apiThunks, ...visualThunks, ...wpfThunks]
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
  `Synthesis agent for the ${cfg.project} QA sweep (${hasWeb ? 'web' : 'WPF-only, SQL correctness'}). You are given confirmed findings:
   ${JSON.stringify(confirmed)}
   Known limitations (report verbatim, not as failures): ${JSON.stringify(cfg.knownLimitations || [])}
   Golden baseline path: ${cfg.baselinePath} (may not exist yet — look for baseline.json there).
   Write a markdown report to ${cfg.reportPath}/report-latest.md with, in order:
   1. Executive gate: PASS if no blocker/major confirmed, else FAIL (one line).
   2. Findings table: severity | area | what broke | repro | verified.
   3. Data-correctness table from the numeric findings (each tab count: cache vs source vs golden).
   4. Drift section: ${isSmoke ? 'this is a SMOKE run — write "drift/baseline skipped (smoke mode)".' : `if ${cfg.baselinePath}/baseline.json exists, diff the current cache counts against its "counts" and flag any tab whose cache/source count no longer matches the blessed value; else write "baseline not yet blessed".`}
   5. Reference any screenshots under ${cfg.reportPath}/shots/.
   6. Known limitations.
   Also write ${cfg.reportPath}/state.json = {date, failures, baselineRef}. Use the date ${nowStr}.
   Return {gate:"PASS"|"FAIL", failures:number, reportPath:string}.`,
  { label: 'synthesis', phase: 'Synthesis',
    schema: { type:'object', required:['gate','failures','reportPath'],
      properties:{ gate:{enum:['PASS','FAIL']}, failures:{type:'number'}, reportPath:{type:'string'} } } }
)

// ---- Exploratory loop (mode-driven; web only — needs live UI to explore) ----
const explored = []
if (mode !== 'once' && hasWeb) {
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
} else if (mode !== 'once' && !hasWeb) {
  log('Exploratory loop skipped — WPF-only app has no HTTP UI to drive.')
}

return { gate: report?.gate, failures: report?.failures, reportPath: report?.reportPath, explored: explored.length, mode }
