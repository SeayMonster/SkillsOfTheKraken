export const meta = {
  name: 'qa-run',
  description: 'Multi-agent QA run: coordinate → parallel per-project checks → finalize',
  phases: [
    { title: 'Coordinate', detail: 'Pre-flight, parse solution, init results.json, launch watcher/dashboard' },
    { title: 'Execute', detail: 'One agent per pending project in parallel (batch up to 4)' },
    { title: 'Finalize', detail: 'Set completed_at and print summary' },
  ],
}

const COORDINATE_SCHEMA = {
  type: 'object',
  required: ['clientName', 'qaBotsRepo', 'resultsPath', 'pendingProjects'],
  properties: {
    clientName: { type: 'string' },
    qaBotsRepo: { type: 'string' },
    resultsPath: { type: 'string' },
    configPath: { type: 'string' },
    pendingProjects: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'path', 'checks'],
        properties: {
          name: { type: 'string' },
          path: { type: 'string' },
          checks: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  },
}

const PROJECT_RESULT_SCHEMA = {
  type: 'object',
  required: ['name', 'status', 'issues'],
  properties: {
    name: { type: 'string' },
    status: { type: 'string' },
    issues: { type: 'array' },
  },
}

const clientRepoRoot = (args && args.clientRepoRoot) || process.cwd()

// --- Phase 1: Coordinate ---

phase('Coordinate')

const coordinated = await agent(
  `You are the Coordinate agent for qa-run.

Client repo root: ${clientRepoRoot}

Steps:
1. Read \`~/.claude/.qa-bots-path\` for QA_BOTS_REPO. If missing, stop: "Run crisp-tc:qa-init first."

2. Client name: run \`Split-Path -Leaf (Get-Location)\` from ${clientRepoRoot}.

3. Read \`QA_BOTS_REPO\\clients\\<name>\\.claude\\qa-config.json\` for solution_path and staging_url.

4. Parse the .sln at solution_path — extract all .csproj paths. Mark *Tests* / *Test* projects as skipped.

5. For each non-test project, detect checks:
   - qa-dapper: using Dapper, SqlMapper, QueryAsync, ExecuteAsync, QueryFirstOrDefault, IDbConnection
   - qa-web-smoke: ApiController, Route(, ControllerBase, WebApplication, app.MapGet, app.MapPost
   - qa-openaccess: UserControlBase, ICommandManager, IPopupControlSubscriber, or .ascx files
   - qa-oa-deployment: qa-openaccess + CopyWebUI.bat present
   - Snowflake: Snowflake.Data, SnowflakeDbConnection, snowflake.net → manual-review only

6. Write results.json to QA_BOTS_REPO\\clients\\<name>\\.qa-run\\results.json with all projects (pending/skipped/manual-review).

7. Launch watcher + report.html dashboard (Start-Process qa-watcher.ps1 and report.html).

8. Return JSON: clientName, qaBotsRepo, resultsPath (full path to results.json), configPath, pendingProjects (array of { name, path, checks } for status pending only).`,
  { phase: 'Coordinate', schema: COORDINATE_SCHEMA, label: 'coordinate' }
)

if (!coordinated) throw new Error('Coordinate phase failed — check qa-init and qa-config.json.')

log(`Client: ${coordinated.clientName} | Pending projects: ${coordinated.pendingProjects.length}`)

// --- Phase 2: Execute (parallel, one agent per project, batches of 4) ---

phase('Execute')

const pending = coordinated.pendingProjects
const batchSize = 4

for (let i = 0; i < pending.length; i += batchSize) {
  const batch = pending.slice(i, i + batchSize)
  await parallel(
    batch.map(proj => () =>
      agent(
        `You are the QA agent for project "${proj.name}".

Project path: ${proj.path}
Checks: ${JSON.stringify(proj.checks)}
Results file: ${coordinated.resultsPath}
Config: ${coordinated.configPath}

Steps:
1. Set this project's status to "running" in results.json (rewrite full file).

2. Run applicable checks:
   - qa-dapper: Invoke crisp-tc:qa-dapper on each .cs file in ${proj.path}
   - qa-web-smoke: Invoke crisp-tc:qa-web-smoke with staging_url from config
   - qa-openaccess: Invoke crisp-tc:qa-openaccess with project path ${proj.path}
   - qa-oa-deployment: Audit .csproj HintPath DLLs vs CopyWebUI.bat copy lines (+ packages.config version warnings)

3. Collect issues as { severity, message }.

4. Resolve status: any error → fail; warnings/info only or none → pass.

5. Update results.json with final status and issues for "${proj.name}".

Return JSON: { name: "${proj.name}", status, issues }.`,
        { phase: 'Execute', schema: PROJECT_RESULT_SCHEMA, label: `project-${proj.name}` }
      )
    )
  )
}

// --- Phase 3: Finalize ---

phase('Finalize')

await agent(
  `You are the Finalize agent for qa-run.

Results file: ${coordinated.resultsPath}
Client: ${coordinated.clientName}

Steps:
1. Read results.json. Set completed_at to current ISO 8601 timestamp. Write file.

2. Print summary:
   QA Complete — <name>
   Pass / Fail / Manual Review / Skipped counts
   Dashboard path`,
  { phase: 'Finalize', label: 'finalize' }
)
