export const meta = {
  name: 'create-saas-deployment-package',
  description: 'Build SaaS deployment package: stage SQL/web, validate, then zip',
  phases: [
    { title: 'Build', detail: 'Gather SQL, clean (strip GO/SET), stage batch + web files' },
    { title: 'Validate', detail: 'Agent checks staged SQL files for Deploy-SQL.ps1 incompatibilities' },
    { title: 'Package', detail: 'Create deploy-web.zip + deploy-batch.zip, cleanup' },
  ],
}

const flag = (args && args.flag) || '--saas'
const repoRoot = (args && args.repoRoot) || ''
if (!repoRoot) throw new Error('repoRoot is required')
const ps1 = 'C:\\Users\\bseay\\source\\repos\\SkillsOfTheKraken\\skills\\create-saas-deployment-package\\scripts\\build-deployment-package.ps1'

// --- Phase 1: Build (Stage) ---
phase('Build')

const BUILD_SCHEMA = {
  type: 'object',
  required: ['succeeded', 'deployDir', 'output'],
  properties: {
    succeeded: { type: 'boolean' },
    deployDir: { type: 'string', description: 'Absolute path printed after "Build folder:" in the output' },
    output: { type: 'string' },
  },
}

const buildResult = await agent(
  `Run the deployment build stage and return structured output.

Steps:
1. Run this PowerShell command and capture ALL stdout/stderr:
   & "${ps1}" -RepoRoot "${repoRoot}" -Flag "${flag}" -Phase "Stage"
2. Return:
   - succeeded: true if output contains "Stage complete", false if it contains Exception/Error/throw
   - deployDir: the path printed on the line starting "Build folder:"
   - output: full stdout/stderr from step 1`,
  { label: 'build-stage', phase: 'Build', schema: BUILD_SCHEMA }
)

if (!buildResult) throw new Error('Build stage returned no output')
if (!buildResult.succeeded) throw new Error('Build stage failed:\n' + buildResult.output)

const deployDir = buildResult.deployDir
log(`Build: ${deployDir} | ` + buildResult.output.split('\n').filter(l => l.trim()).slice(-3).join(' | '))

// --- Phase 2: Validate ---
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
        required: ['file', 'issue'],
        properties: {
          file: { type: 'string' },
          issue: { type: 'string' },
          fix: { type: 'string' },
        },
      },
    },
  },
}

const sqlDir = `${deployDir}\\stage-batch\\SQL`

const validation = await agent(
  `Validate staged SQL files for Deploy-SQL.ps1 / ADO.NET compatibility.

SQL directory: ${sqlDir}

Steps:
1. List all *.sql files in that directory (use PowerShell or Glob).
2. Read each file's full contents.
3. Check EACH file for these specific issues — these cause runtime errors in Deploy-SQL.ps1 (ADO.NET ExecuteNonQuery):
   a) Standalone GO line (line that is ONLY "GO" optionally with whitespace) — ADO.NET rejects GO
   b) SET ANSI_NULLS statement — causes "CREATE/ALTER PROCEDURE must be first statement in batch"
   c) SET QUOTED_IDENTIFIER statement — same error as above
   d) USE <database> statement — wrong database targeting
4. Comments (-- comment lines) before CREATE/ALTER are FINE. Do not flag them.
5. Return passed=true and empty issues array if all files are clean.
6. Return passed=false with one issue entry per problem found (file=filename, issue=description, fix=how to fix).`,
  { label: 'validate-sql', phase: 'Validate', schema: VALIDATE_SCHEMA }
)

if (!validation) throw new Error('Validate agent returned no result')

if (!validation.passed) {
  const issueLines = validation.issues.map(i => `  ${i.file}: ${i.issue}${i.fix ? ' -- Fix: ' + i.fix : ''}`).join('\n')
  throw new Error(`SQL validation failed -- fix these before packaging:\n${issueLines}`)
}

log(`Validation passed: ${validation.summary || validation.issues.length + ' issues checked, all clean'}`)

// --- Phase 3: Package (Zip) ---
phase('Package')

const packageResult = await agent(
  `Run this exact PowerShell command and return ALL output verbatim. Do not summarize.

& "${ps1}" -RepoRoot "${repoRoot}" -Flag "${flag}" -Phase "Zip"

Return every line of stdout and stderr.`,
  { label: 'package-zip', phase: 'Package' }
)

if (!packageResult) throw new Error('Package phase returned no output')

log(packageResult.split('\n').filter(l => l.trim()).join(' | '))

return {
  status: 'complete',
  deployDir,
  validationSummary: validation.summary,
  output: packageResult,
}
