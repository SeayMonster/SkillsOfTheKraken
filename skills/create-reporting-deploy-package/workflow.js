export const meta = {
  name: 'create-reporting-deploy-package',
  description: 'IIS deploy packager for ASP.NET Core: validate → publish → configure → ZIP',
  phases: [
    { title: 'Validate', detail: 'Find web .csproj, detect framework, run dotnet build' },
    { title: 'Publish', detail: 'dotnet publish Release to temp dir' },
    { title: 'Configure', detail: 'Write appsettings.Production.json + web.config in parallel' },
    { title: 'Package', detail: 'Generate DEPLOY-README.md, ZIP to batch deploy path' },
  ],
}

const { repoRoot } = args

const VALIDATE_SCHEMA = {
  type: 'object',
  required: ['projectPath', 'targetFramework', 'assemblyName', 'iisSiteName', 'iisAppPool'],
  properties: {
    projectPath:     { type: 'string' },
    targetFramework: { type: 'string' },
    assemblyName:    { type: 'string' },
    iisSiteName:     { type: 'string' },
    iisAppPool:      { type: 'string' },
  },
}

const PUBLISH_SCHEMA = {
  type: 'object',
  required: ['publishDir'],
  properties: { publishDir: { type: 'string' } },
}

// --- Phase 1: Validate ---

phase('Validate')

const validated = await agent(
  `You are the Validate agent for the IIS deploy packager.

Repo root: ${repoRoot}

Steps:
1. Read \`${repoRoot}/_deploy-request.json\`.
   Extract: environment, serverName, connectionString.
   Apply defaults: iisSiteName = value or "CrispReporting", iisAppPool = value or "CrispReporting".

2. Find the ASP.NET Core web project. Run this PowerShell:
   $found = Get-ChildItem "${repoRoot}" -Recurse -Filter "*.csproj" | Where-Object { (Get-Content $_.FullName -Raw) -match 'Sdk="Microsoft\\.NET\\.Sdk\\.Web"' }
   $found | Select-Object -ExpandProperty FullName

   - If 0 results: stop with "No ASP.NET Core web project found in ${repoRoot}. Ensure a .csproj with Sdk=\\"Microsoft.NET.Sdk.Web\\" exists."
   - If 2+ results: stop with "Multiple web projects found:\\n<list paths>\\nAdd a \\"projectPath\\" field to _deploy-request.json to specify which one to publish."
   - If 1 result: use it as projectPath.

   Note: if _deploy-request.json contains a "projectPath" field, use that directly and skip the scan.

3. Read <TargetFramework> from the .csproj:
   $content = Get-Content "<projectPath>" -Raw
   if ($content -match '<TargetFramework>(.*?)<\\/TargetFramework>') { $Matches[1] } else { "net8.0" }

4. Read <AssemblyName> from the .csproj. If not found, use the .csproj filename without extension:
   if ($content -match '<AssemblyName>(.*?)<\\/AssemblyName>') { $Matches[1] } else { [System.IO.Path]::GetFileNameWithoutExtension("<projectPath>") }

5. Run dotnet build:
   dotnet build "<projectPath>" -c Release --nologo -v minimal
   If exit code != 0: stop with the build error output.

6. Return structured output: projectPath, targetFramework, assemblyName, iisSiteName, iisAppPool.`,
  { phase: 'Validate', schema: VALIDATE_SCHEMA, label: 'validate' }
)

if (!validated) throw new Error('Validate phase failed — check build errors above.')

log(`Project: ${validated.projectPath} | Framework: ${validated.targetFramework} | Assembly: ${validated.assemblyName}`)

// --- Phase 2: Publish ---

phase('Publish')

const published = await agent(
  `You are the Publish agent.

Project path: ${validated.projectPath}
Target framework: ${validated.targetFramework}

Steps:
1. Create a clean temp publish directory:
   $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "crisp-reporting-deploy"
   if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
   New-Item -ItemType Directory -Force $tmpDir | Out-Null

2. Run dotnet publish:
   dotnet publish "${validated.projectPath}" -c Release -f ${validated.targetFramework} -o $tmpDir --nologo -v minimal
   If exit code != 0: stop with "dotnet publish failed: <error output>"

3. Return publishDir = the resolved absolute path of $tmpDir.`,
  { phase: 'Publish', schema: PUBLISH_SCHEMA, label: 'publish' }
)

if (!published) throw new Error('Publish phase failed.')

log(`Published to: ${published.publishDir}`)

// --- Phase 3: Configure (parallel) ---

phase('Configure')

await parallel([
  () => agent(
    `You are the AppSettings agent.

Publish dir: ${published.publishDir}
Repo root: ${repoRoot}

Steps:
1. Read \`${repoRoot}/_deploy-request.json\` and extract connectionString.
2. Write \`${published.publishDir}/appsettings.Production.json\`:
{
  "ConnectionStrings": {
    "DefaultConnection": "<connectionString value>"
  }
}
3. Return "appsettings.Production.json written."`,
    { phase: 'Configure', label: 'appsettings' }
  ),

  () => agent(
    `You are the WebConfig agent.

Publish dir: ${published.publishDir}
Assembly name: ${validated.assemblyName}

Steps:
1. Write \`${published.publishDir}/web.config\` with this exact content (substitute assemblyName):
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <location path="." inheritInChildApplications="false">
    <system.webServer>
      <handlers>
        <add name="aspNetCore" path="*" verb="*"
             modules="AspNetCoreModuleV2" resourceType="Unspecified" />
      </handlers>
      <aspNetCore processPath="dotnet"
                  arguments=".\\${validated.assemblyName}.dll"
                  stdoutLogEnabled="false"
                  stdoutLogFile=".\\logs\\stdout"
                  hostingModel="inprocess" />
    </system.webServer>
  </location>
</configuration>
2. Return "web.config written."`,
    { phase: 'Configure', label: 'web-config' }
  ),
])

log('appsettings.Production.json and web.config written.')

// --- Phase 4: Package ---

phase('Package')

const DEPLOY_PATH = 'G:\\My Drive\\!ai\\BY SaaS\\batch'

await agent(
  `You are the Package agent.

Publish dir: ${published.publishDir}
Repo root: ${repoRoot}
Assembly name: ${validated.assemblyName}
Target framework: ${validated.targetFramework}
Batch deploy path: ${DEPLOY_PATH}

Steps:
1. Read \`${repoRoot}/_deploy-request.json\` for: environment, serverName, iisSiteName (default "CrispReporting"), iisAppPool (default "CrispReporting").

2. Get today's date: $date = Get-Date -Format "yyyy-MM-dd"

3. Write \`${published.publishDir}/DEPLOY-README.md\`:

# IIS Deployment Guide — <environment>
Generated: <$date>

## Prerequisites
- Windows Server with IIS enabled
- ASP.NET Core Hosting Bundle (${validated.targetFramework}) installed
- ASP.NET Core Module V2 (included in Hosting Bundle)

## IIS Setup (first-time only)
1. Open IIS Manager on <serverName>
2. Create Application Pool named <iisAppPool>
   - .NET CLR version: No Managed Code
   - Pipeline mode: Integrated
3. Create Website named <iisSiteName>
   - Physical path: target folder (e.g. C:\\inetpub\\wwwroot\\CrispReporting)
   - Application pool: <iisAppPool>
   - Binding: configure http/https port as needed

## Deployment Steps
1. Stop the <iisSiteName> site or <iisAppPool> app pool
2. Extract the ZIP contents into the physical path (overwrite all files)
3. Verify appsettings.Production.json has the correct connection string
4. Start the app pool and site
5. Browse to the site and confirm the dashboard loads

## Connection String
Location: appsettings.Production.json -> ConnectionStrings.DefaultConnection

4. Create the ZIP:
   $zipName = "<environment>-$date.zip"

   Check if deploy path is accessible: Test-Path "${DEPLOY_PATH}"
   If yes: $zipDest = "${DEPLOY_PATH}\\$zipName"
   If no:
     $zipDest = (Join-Path (Split-Path "${published.publishDir}" -Parent) $zipName)
     Write-Host "WARNING: Batch deploy path not accessible. Dropping ZIP to: $zipDest"

   if (Test-Path $zipDest) { Remove-Item $zipDest -Force }
   $items = Get-ChildItem "${published.publishDir}" | Select-Object -ExpandProperty FullName
   Compress-Archive -Path $items -DestinationPath $zipDest -Force

5. Return "Package created: <zipDest>"`,
  { phase: 'Package', label: 'package' }
)

log('IIS deploy package complete.')

return { status: 'complete', publishDir: published.publishDir }
