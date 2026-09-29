export const meta = {
  name: 'package-hershey-dashboard',
  description: 'Build+zip the Hershey WPF dashboard, validate the package, optionally deploy the CrispReporting SQL',
  phases: [
    { title: 'Build', detail: 'Publish WPF app + zip via Publish-HersheyDashboard.ps1' },
    { title: 'Validate', detail: 'Agent checks package contents (exe/dll/html present, local config excluded)' },
    { title: 'SQL', detail: 'Deploy CrispReporting SQL via Deploy-ReportingSql.ps1 (dry-run unless execute)' },
  ],
}

// --- Args (from the SKILL.md Workflow invocation) ---
const flag = (args && args.flag) || '--build'
const repoRoot = (args && args.repoRoot) || 'C:\\Users\\bseay\\source\\repos\\Hershey\\New Reports\\H.-Reports'
const execute = !!(args && args.execute)
const selfContained = !!(args && args.selfContained)
const skipSeed = !!(args && args.skipSeed)

const doBuild = flag === '--build' || flag === '--all'
const doSql = flag === '--sql' || flag === '--all'

const publishPs1 = `${repoRoot}\\HersheyDashboard\\deploy\\Publish-HersheyDashboard.ps1`
const sqlPs1 = `${repoRoot}\\ReportingDashboard\\sql\\deploy\\Deploy-ReportingSql.ps1`

let buildResult = null
let validation = null
let sqlResult = null

// --- Phase 1: Build (publish + zip) ---
if (doBuild) {
  phase('Build')

  const BUILD_SCHEMA = {
    type: 'object',
    required: ['succeeded', 'output'],
    properties: {
      succeeded: { type: 'boolean', description: 'true if the RECEIPT printed and a Zip path exists; false on Exception/Error/failed' },
      zipPath: { type: 'string', description: 'the .zip path from the RECEIPT "Zip :" line' },
      fileCount: { type: 'integer', description: 'the "Files :" count from the RECEIPT' },
      dllLastWrite: { type: 'string', description: 'the "Built HersheyDashboard.dll LastWrite=" timestamp' },
      output: { type: 'string', description: 'full stdout/stderr' },
    },
  }

  buildResult = await agent(
    `Publish and package the Hershey WPF dashboard. Run this PowerShell command and capture ALL stdout/stderr:

    & "${publishPs1}"${selfContained ? ' -SelfContained' : ''}

The script builds the app, copies the served HTML, EXCLUDES the per-machine connection config, and zips the result. Then return:
- succeeded: true if the output contains "Done." AND a "Zip :" line; false if it contains Exception / Error / throw / "failed".
- zipPath: the path from the RECEIPT "Zip :" line (strip the trailing size in parentheses).
- fileCount: the integer from the RECEIPT "Files :" line.
- dllLastWrite: the timestamp from the "Built HersheyDashboard.dll  LastWrite=" line.
- output: the full stdout/stderr, verbatim.`,
    { label: 'build-publish', phase: 'Build', schema: BUILD_SCHEMA }
  )

  if (!buildResult) throw new Error('Build phase returned no output')
  if (!buildResult.succeeded) throw new Error('Build failed:\n' + buildResult.output)
  log(`Zip: ${buildResult.zipPath} | files=${buildResult.fileCount} | dll=${buildResult.dllLastWrite}`)

  // --- Phase 2: Validate the package contents ---
  phase('Validate')

  const VALIDATE_SCHEMA = {
    type: 'object',
    required: ['passed', 'issues'],
    properties: {
      passed: { type: 'boolean' },
      summary: { type: 'string' },
      issues: {
        type: 'array',
        items: {
          type: 'object',
          required: ['item', 'issue'],
          properties: {
            item: { type: 'string' },
            issue: { type: 'string' },
            fix: { type: 'string' },
          },
        },
      },
    },
  }

  validation = await agent(
    `Validate the deployment package the build just produced. The zip is at:
    ${buildResult.zipPath}

Steps:
1. Expand it to a scratch folder, e.g.:
   Expand-Archive -Path "${buildResult.zipPath}" -DestinationPath "$env:TEMP\\hd_pkg_check" -Force
2. Confirm these files are PRESENT (under the package's app folder):
   - HersheyDashboard.exe
   - HersheyDashboard.dll
   - HersheyDashboard.html   (the served UI — without it the WebView2 host renders nothing)
   - DEPLOY.txt
3. Confirm connectionStrings.local.config is ABSENT. It must never ship — the target box keeps its own connection. (connectionStrings.local.config.template MAY be present; that's fine.)
4. Return passed=true with an empty issues array if every check holds. Otherwise passed=false with one issue per problem: item (what), issue (what's wrong), fix (how to resolve).
5. Remove the scratch folder when done.`,
    { label: 'validate-package', phase: 'Validate', schema: VALIDATE_SCHEMA }
  )

  if (!validation) throw new Error('Validate phase returned no result')
  if (!validation.passed) {
    const lines = validation.issues.map(i => `  ${i.item}: ${i.issue}${i.fix ? ' -- Fix: ' + i.fix : ''}`).join('\n')
    throw new Error(`Package validation failed -- do NOT deploy this zip:\n${lines}`)
  }
  log(`Package valid: ${validation.summary || 'exe/dll/html present, local config excluded'}`)
}

// --- Phase 3: SQL deploy (dry-run unless execute) ---
if (doSql) {
  phase('SQL')

  const SQL_SCHEMA = {
    type: 'object',
    required: ['succeeded', 'output'],
    properties: {
      succeeded: { type: 'boolean', description: 'true on "DRY RUN COMPLETE" or "Reporting SQL deployed"; false on Exception/Error/failed' },
      executed: { type: 'boolean', description: 'true only if it actually deployed (not a dry run)' },
      server: { type: 'string', description: 'the server it parsed from config or was overridden to' },
      output: { type: 'string' },
    },
  }

  sqlResult = await agent(
    `Deploy (or preview) the ReportingDashboard CrispReporting SQL. Run this PowerShell command and capture ALL stdout/stderr:

    & "${sqlPs1}"${execute ? ' -Execute -Force' : ''}${skipSeed ? ' -SkipSeed' : ''}

Notes:
- Without -Execute this is a DRY RUN: it parses the server from connectionStrings.local.config, prints the ordered plan, tests connectivity, and makes NO changes.
- With -Execute it deploys the ordered, idempotent SQL (creates CrispReporting if needed).
Return:
- succeeded: true if the output contains "DRY RUN COMPLETE" (dry run) or "Reporting SQL deployed" (executed); false on Exception / Error / throw / "failed".
- executed: ${execute}  (true only if it actually deployed).
- server: the value from the "Server parsed from config:" or "Server (override):" line.
- output: the full stdout/stderr, verbatim.`,
    { label: execute ? 'sql-deploy' : 'sql-dryrun', phase: 'SQL', schema: SQL_SCHEMA }
  )

  if (!sqlResult) throw new Error('SQL phase returned no output')
  if (!sqlResult.succeeded) throw new Error('SQL phase failed:\n' + sqlResult.output)
  log(`SQL ${sqlResult.executed ? 'DEPLOYED' : 'dry-run'} on ${sqlResult.server}`)
}

return {
  status: 'complete',
  flag,
  build: buildResult ? { zipPath: buildResult.zipPath, fileCount: buildResult.fileCount, dllLastWrite: buildResult.dllLastWrite } : null,
  packageValid: validation ? validation.passed : null,
  sql: sqlResult ? { executed: sqlResult.executed, server: sqlResult.server } : null,
}
