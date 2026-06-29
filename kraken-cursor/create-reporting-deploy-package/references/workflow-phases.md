# Workflow phases — kraken-cursor-create-reporting-deploy-package

Parent agent: execute phases in order. Launch parallel Task subagents in a **single message** when marked PARALLEL.

Task settings: `subagent_type: generalPurpose`, `model` optional, pass the full prompt below as `prompt`.

State file: `{repoRoot}/.kraken-cursor/deploy-state-working.json`

---

## Phase 1: Validate

**Single Task or parent executes directly.**

```
You are the Validate agent for the IIS deploy packager.

Repo root: {repoRoot}
Skill dir: {SKILL_DIR}

Steps:
1. Read `{repoRoot}/_deploy-request.json`.
   Extract: environment, serverName, connectionString.
   Apply defaults: iisSiteName = value or "CrispReporting", iisAppPool = value or "CrispReporting".

2. Find the ASP.NET Core web project. Run this PowerShell:
   $found = Get-ChildItem "{repoRoot}" -Recurse -Filter "*.csproj" | Where-Object { (Get-Content $_.FullName -Raw) -match 'Sdk="Microsoft\.NET\.Sdk\.Web"' }
   $found | Select-Object -ExpandProperty FullName

   - If 0 results: stop with "No ASP.NET Core web project found in {repoRoot}. Ensure a .csproj with Sdk=\"Microsoft.NET.Sdk.Web\" exists."
   - If 2+ results: stop with "Multiple web projects found:\n<list paths>\nAdd a \"projectPath\" field to _deploy-request.json to specify which one to publish."
   - If 1 result: use it as projectPath.

   Note: if _deploy-request.json contains a "projectPath" field, use that directly and skip the scan.

3. Read <TargetFramework> from the .csproj:
   $content = Get-Content "<projectPath>" -Raw
   if ($content -match '<TargetFramework>(.*?)</TargetFramework>') { $Matches[1] } else { "net8.0" }

4. Read <AssemblyName> from the .csproj. If not found, use the .csproj filename without extension:
   if ($content -match '<AssemblyName>(.*?)</AssemblyName>') { $Matches[1] } else { [System.IO.Path]::GetFileNameWithoutExtension("<projectPath>") }

5. Run dotnet build:
   dotnet build "<projectPath>" -c Release --nologo -v minimal
   If exit code != 0: stop with the build error output.

6. Return structured JSON with keys: projectPath, targetFramework, assemblyName, iisSiteName, iisAppPool.

Write the JSON to {repoRoot}/.kraken-cursor/deploy-state-working.json under key "validated".
Return the JSON in your response.
```

---

## Phase 2: Publish

**Single Task.**

```
You are the Publish agent.

Project path: {projectPath from validated}
Target framework: {targetFramework from validated}

Steps:
1. Create a clean temp publish directory:
   $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "crisp-reporting-deploy"
   if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
   New-Item -ItemType Directory -Force $tmpDir | Out-Null

2. Run dotnet publish:
   dotnet publish "{projectPath}" -c Release -f {targetFramework} -o $tmpDir --nologo -v minimal
   If exit code != 0: stop with "dotnet publish failed: <error output>"

3. Return publishDir = the resolved absolute path of $tmpDir.

Write publishDir to {repoRoot}/.kraken-cursor/deploy-state-working.json under key "publishDir".
Return publishDir in your response.
```

---

## Phase 3: Configure (PARALLEL — 2 Tasks)

Launch both Task subagents in a **single message**.

### 3a AppSettings

```
You are the AppSettings agent.

Publish dir: {publishDir from state}
Repo root: {repoRoot}

Steps:
1. Read `{repoRoot}/_deploy-request.json` and extract connectionString.
2. Write `{publishDir}/appsettings.Production.json`:
{
  "ConnectionStrings": {
    "DefaultConnection": "<connectionString value>"
  }
}
3. Return "appsettings.Production.json written."
```

### 3b WebConfig

```
You are the WebConfig agent.

Publish dir: {publishDir from state}
Assembly name: {assemblyName from validated}

Steps:
1. Write `{publishDir}/web.config` with this exact content (substitute assemblyName):
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <location path="." inheritInChildApplications="false">
    <system.webServer>
      <handlers>
        <add name="aspNetCore" path="*" verb="*"
             modules="AspNetCoreModuleV2" resourceType="Unspecified" />
      </handlers>
      <aspNetCore processPath="dotnet"
                  arguments=".\\{assemblyName}.dll"
                  stdoutLogEnabled="false"
                  stdoutLogFile=".\\logs\\stdout"
                  hostingModel="inprocess" />
    </system.webServer>
  </location>
</configuration>
2. Return "web.config written."
```

Parent: after both complete, set `configureComplete: true` in the state file.

---

## Phase 4: Package

**Single Task or parent + Shell.**

```
You are the Package agent.

Publish dir: {publishDir from state}
Repo root: {repoRoot}
Assembly name: {assemblyName from validated}
Target framework: {targetFramework from validated}
Batch deploy path: {batchDeployPath}

Steps:
1. Read `{repoRoot}/_deploy-request.json` for: environment, serverName, iisSiteName (default "CrispReporting"), iisAppPool (default "CrispReporting").
   If `batchDeployPath` is set in the file, use it as {batchDeployPath}. Otherwise leave {batchDeployPath} empty.

2. Get today's date: $date = Get-Date -Format "yyyy-MM-dd"

3. Write `{publishDir}/DEPLOY-README.md`:

# IIS Deployment Guide — <environment>
Generated: <$date>

## Prerequisites
- Windows Server with IIS enabled
- ASP.NET Core Hosting Bundle ({targetFramework}) installed
- ASP.NET Core Module V2 (included in Hosting Bundle)

## IIS Setup (first-time only)
1. Open IIS Manager on <serverName>
2. Create Application Pool named <iisAppPool>
   - .NET CLR version: No Managed Code
   - Pipeline mode: Integrated
3. Create Website named <iisSiteName>
   - Physical path: target folder (e.g. C:\inetpub\wwwroot\CrispReporting)
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

   If {batchDeployPath} is non-empty and Test-Path "{batchDeployPath}":
     $zipDest = Join-Path "{batchDeployPath}" $zipName
   Else:
     $zipDest = Join-Path (Split-Path "{publishDir}" -Parent) $zipName
     Write-Host "WARNING: Batch deploy path not accessible or not configured. Dropping ZIP to: $zipDest"

   if (Test-Path $zipDest) { Remove-Item $zipDest -Force }
   $items = Get-ChildItem "{publishDir}" | Select-Object -ExpandProperty FullName
   Compress-Archive -Path $items -DestinationPath $zipDest -Force

5. Return "Package created: <zipDest>"
```

Report the full ZIP path to the user when complete.
