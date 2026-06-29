export const meta = {
  name: 'client-onboarding',
  description: 'Multi-agent client onboarding: coordinate → parallel artifact generation → wire → finalize',
  phases: [
    { title: 'Coordinate', detail: 'Scan csproj, tag projects, detect env Excel, check prerequisites' },
    { title: 'Generate', detail: 'Parallel: client.json, README, Setup.ps1, portal HTML, ONBOARDING.md' },
    { title: 'Wire', detail: 'Parallel: copilot/CLAUDE append, gitignore, CopyWebUI.bat, sln _Portal' },
    { title: 'Finalize', detail: 'Commit reminder, switch-database, MCP verify' },
  ],
}

const COORDINATE_SCHEMA = {
  type: 'object',
  required: ['repoRoot', 'clientName', 'portalFileName', 'projects', 'environmentExcel'],
  properties: {
    repoRoot: { type: 'string' },
    clientName: { type: 'string' },
    portalFileName: { type: 'string' },
    projects: { type: 'array' },
    environmentExcel: { type: 'string' },
    needsSetupCopilot: { type: 'boolean' },
    needsEnvSwitcher: { type: 'boolean' },
  },
}

const repoRoot = (args && args.repoRoot) || process.cwd()

phase('Coordinate')

const coordinated = await agent(
  `You are the Coordinate agent for client-onboarding.

Repo root: ${repoRoot}

Steps 1–3 from client-onboarding SKILL.md:
1. Scan .csproj files — ask user to tag each web/batch/skip.
2. Detect environment Excel path.
3. Check Switch-SqlEnv.ps1, copilot-instructions.md, client.json overwrite.

Return JSON: repoRoot, clientName (folder name), portalFileName (e.g. Academy.html),
projects array [{ name, path, target }], environmentExcel path,
needsSetupCopilot, needsEnvSwitcher booleans.`,
  { phase: 'Coordinate', schema: COORDINATE_SCHEMA, label: 'coordinate' }
)

if (!coordinated) throw new Error('Coordinate phase failed.')

if (coordinated.needsSetupCopilot) {
  log('Invoke kraken:setup-copilot before or after Wire phase.')
}

log(`Generating artifacts for ${coordinated.clientName} (${coordinated.projects.length} projects)`)

phase('Generate')

await parallel([
  () => agent(
    `Write client.json to ${coordinated.repoRoot} per Step 4. Projects: ${JSON.stringify(coordinated.projects)}. Excel: ${coordinated.environmentExcel}.`,
    { phase: 'Generate', label: 'client-json' }
  ),
  () => agent(
    `Write README.md to ${coordinated.repoRoot} per Step 5. Client: ${coordinated.clientName}.`,
    { phase: 'Generate', label: 'readme' }
  ),
  () => agent(
    `Write Setup.ps1 to ${coordinated.repoRoot} per Step 6. Idempotent onboarding script.`,
    { phase: 'Generate', label: 'setup-ps1' }
  ),
  () => agent(
    `Write ${coordinated.portalFileName} portal HTML to ${coordinated.repoRoot} per Step 7. Full portal spec in SKILL.md.`,
    { phase: 'Generate', label: 'portal-html' }
  ),
  () => agent(
    `Write ONBOARDING.md to ${coordinated.repoRoot} per Step 8.`,
    { phase: 'Generate', label: 'onboarding-md' }
  ),
])

phase('Wire')

await parallel([
  () => agent(
    `Append deploy package + client.json sections to .github/copilot-instructions.md per Step 9. Repo: ${coordinated.repoRoot}.`,
    { phase: 'Wire', label: 'copilot' }
  ),
  () => agent(
    `Append auto-trigger section to CLAUDE.md per Step 10. Repo: ${coordinated.repoRoot}.`,
    { phase: 'Wire', label: 'claude-md' }
  ),
  () => agent(
    `Update .gitignore per Step 11. Repo: ${coordinated.repoRoot}.`,
    { phase: 'Wire', label: 'gitignore' }
  ),
  () => agent(
    `Update CopyWebUI.bat DEPLOY_TARGET pattern for web projects per Step 12. Repo: ${coordinated.repoRoot}.`,
    { phase: 'Wire', label: 'copywebui' }
  ),
  () => agent(
    `Add _Portal solution folder to .sln per Step 13. Portal: ${coordinated.portalFileName}. Repo: ${coordinated.repoRoot}.`,
    { phase: 'Wire', label: 'sln-portal' }
  ),
])

phase('Finalize')

await agent(
  `Finalize client-onboarding for ${coordinated.clientName}.
Remind user: git commit per Step 14, run switch-database, restart Claude Code, verify /mcp.
List all files created.`,
  { phase: 'Finalize', label: 'finalize' }
)
