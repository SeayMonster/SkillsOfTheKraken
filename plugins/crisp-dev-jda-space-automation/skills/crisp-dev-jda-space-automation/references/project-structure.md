# SA Pro Script Project Structure

Every converted legacy script **must live in its own standalone Visual Studio project**.
Do NOT place multiple converted scripts in a single shared project.

---

## Folder Layout

Follow the same two-level nesting the sample projects use:

```
SolutionRoot\
  ScriptName\                        ← outer folder (matches script name)
    ScriptName\                      ← inner folder / project folder
      ScriptName.csproj
      SpaceMenuClass.cs              ← Space Planning script
      (or FloorMenuClass.cs)         ← Floor Planning script
      HelperClasses\
        CommandFactory.cs
        ConfigurationHelper.cs
      Properties\
        AssemblyInfo.cs
      App.Config
      appSettings.json
      packages.config
```

**Examples from this solution:**
- `CX_ArchivePlanograms\CX_ArchivePlanograms\` — Space Planning script
- `CX_ArchiveFloorplans\CX_ArchiveFloorplans\` — Floor Planning script

---

## .csproj — Non-Negotiable Settings

```xml
<OutputType>Library</OutputType>          <!-- MUST be Library, not Exe -->
<RootNamespace>SpaceMenuAssembly</RootNamespace>   <!-- Space Planning -->
<RootNamespace>FloorMenuAssembly</RootNamespace>   <!-- Floor Planning -->
<TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
```

---

## JDA DLL References — Registry Path (No Libraries Folder)

All JDA/Blue Yonder DLLs resolve from the SA Pro install directory via registry.
Do NOT copy DLLs into a Libraries folder — use this pattern:

```xml
<Reference Include="JDA.Intactix.Automation">
  <HintPath>$(Registry:HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Intactix@JDA_SpaceAutomation_Pro)JDA.Intactix.Automation.dll</HintPath>
  <Private>true</Private>
</Reference>
<Reference Include="JDA.Intactix.Automation.Enumerations">
  <HintPath>$(Registry:HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Intactix@JDA_SpaceAutomation_Pro)JDA.Intactix.Automation.Enumerations.dll</HintPath>
  <Private>true</Private>
</Reference>
```

If the script uses `IKBDbSupport` (Dapper DB calls), also include:

```xml
<Reference Include="JDA.Intactix.Common">
  <HintPath>$(Registry:...)JDA.Intactix.Common.dll</HintPath>
  <Private>true</Private>
</Reference>
<Reference Include="JDA.Intactix.Configuration">
  <HintPath>$(Registry:...)JDA.Intactix.Configuration.dll</HintPath>
  <Private>true</Private>
</Reference>
<Reference Include="JDA.Intactix.DataAccess">
  <HintPath>$(Registry:...)JDA.Intactix.DataAccess.dll</HintPath>
  <Private>true</Private>
</Reference>
<Reference Include="JDA.Intactix.IKB.Common">
  <HintPath>$(Registry:...)JDA.Intactix.IKB.Common.dll</HintPath>
  <Private>true</Private>
</Reference>
<Reference Include="JDA.Intactix.IKB.DataAccess">
  <HintPath>$(Registry:...)JDA.Intactix.IKB.DataAccess.dll</HintPath>
  <Private>true</Private>
</Reference>
```

The full registry key: `$(Registry:HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Intactix@JDA_SpaceAutomation_Pro)`

---

## NuGet Packages (packages.config)

```xml
<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="Dapper" version="2.1.35" targetFramework="net48" />
  <package id="Serilog" version="3.1.1" targetFramework="net48" />
  <package id="Serilog.Sinks.RollingFileAlternate" version="2.0.9" targetFramework="net48" />
</packages>
```

NuGet HintPaths use `$(SolutionDir)packages\...` (resolved at solution level):

```xml
<Reference Include="Dapper">
  <HintPath>$(SolutionDir)packages\Dapper.2.1.35\lib\net461\Dapper.dll</HintPath>
</Reference>
<Reference Include="Serilog">
  <HintPath>$(SolutionDir)packages\Serilog.3.1.1\lib\net462\Serilog.dll</HintPath>
</Reference>
<Reference Include="Serilog.Sinks.RollingFileAlternate">
  <HintPath>$(SolutionDir)packages\Serilog.Sinks.RollingFileAlternate.2.0.9\lib\net45\Serilog.Sinks.RollingFileAlternate.dll</HintPath>
</Reference>
```

---

## Required MSBuild Targets

Copy these exactly — they embed the SA Pro license and update the output config:

```xml
<UsingTask AssemblyFile="$(Registry:HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Intactix@JDA_SpaceAutomation_Pro)JDA.Intactix.Automation.Tasks.dll" TaskName="UpdateAssemblyInfo" />
<UsingTask AssemblyFile="$(Registry:HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Intactix@JDA_SpaceAutomation_Pro)JDA.Intactix.Automation.Tasks.dll" TaskName="UpdateAppConfigFiles" />

<Target Name="TransformOnBuild" AfterTargets="BeforeBuild">
  <Delete Files="License.lic" ContinueOnError="true" />
  <UpdateAssemblyInfo Param1="{project-guid-lowercase-no-braces}"
                      ReferencePath1="$(ProjectDir)"
                      ReferencePath="$(Registry:HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Intactix@JDA_SpaceAutomation_Pro)">
    <Output PropertyName="LicenseString" TaskParameter="LicenseString" />
  </UpdateAssemblyInfo>
  <ItemGroup>
    <EmbeddedResource Include="License.lic" />
  </ItemGroup>
</Target>

<Target Name="AfterBuild" />

<Target Name="AfterBuildEvent" AfterTargets="AfterBuild">
  <UpdateAppConfigFiles
    appConfigLocation="$(OutDir)\$(TargetFileName).config"
    configPath="$(Registry:HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Intactix@JDA_SpaceAutomation_Pro)SpaceAutomationPro.config">
  </UpdateAppConfigFiles>
  <ItemGroup>
    <EmbeddedResource Remove="License.lic" />
  </ItemGroup>
</Target>
```

`Param1` must be the project GUID in lowercase without braces. Match it to the `<ProjectGuid>` value.

---

## App.Config — SA Pro Format

Use the SA Pro config format with a standard `<appSettings>` block added for script-specific settings.
The `<configSections>` and JDA-encrypted sections are required by the SA Pro runtime:

```xml
<?xml version="1.0"?>
<configuration>
  <configSections>
    <sectionGroup name="ApplicationSettings">
      <section name="applicationSetting"
               type="JDA.Intactix.Configuration.NameValueSection, JDA.Intactix.Configuration"/>
    </sectionGroup>
    <sectionGroup name="jda.intactix.ikb">
      <section name="databaseSettings"
               type="JDA.Intactix.Configuration.DbConfigurationSection, JDA.Intactix.Configuration"/>
      <section name="defaultSettings"
               type="JDA.Intactix.Configuration.DbConfigurationSection, JDA.Intactix.Configuration"/>
      <section name="webApiSettings"
               type="JDA.Intactix.Configuration.WebApiConfigurationSection, JDA.Intactix.Configuration" />
    </sectionGroup>
  </configSections>

  <!-- Script-specific settings — update values per environment -->
  <appSettings>
    <add key="LogDirectory"     value="C:\Logs\ScriptName" />
    <add key="CKBDatabaseAlias" value="[alias] | [server] | " />
    <add key="ServerName"       value="[server]" />
    <add key="DatabaseName"     value="[database]" />
    <add key="CustomSchema"     value="[your_schema]" />
    <!-- add script-specific keys here -->
  </appSettings>

  <!-- SA Pro encrypted DB settings — do not modify manually -->
  <jda.intactix.ikb>
    <databaseSettings configProtectionProvider="SAProConfigurationEncrypter">
      <EncryptedData><!-- encrypted blob from SA Pro --></EncryptedData>
    </databaseSettings>
    <defaultSettings configProtectionProvider="SAProConfigurationEncrypter">
      <EncryptedData><!-- encrypted blob from SA Pro --></EncryptedData>
    </defaultSettings>
    <webApiSettings gatewayUrl="" protocolVersion="V1" throttleCount="10" clientId="" realm="" />
  </jda.intactix.ikb>
  <ApplicationSettings>
    <applicationSetting>
      <add name="LogFilePath" value=""/>
      <add name="StartSpacePlanning" value="true" />
      <add name="StartFloorPlanning" value="true" />
      <add name="UseWebApi" value="false" />
    </applicationSetting>
  </ApplicationSettings>
  <configProtectedData defaultProvider="SAProConfigurationEncrypter">
    <providers>
      <add name="SAProConfigurationEncrypter"
           type="JDA.Intactix.Automation.Helper.SAProConfigurationEncrypter,JDA.Intactix.Automation" />
    </providers>
  </configProtectedData>
</configuration>
```

---

## AssemblyInfo.cs

```csharp
using System.Reflection;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("SpaceMenuAssembly")]       // or FloorMenuAssembly
[assembly: AssemblyDescription("Script description")]
[assembly: AssemblyCompany("Blue Yonder Group, Inc.")]
[assembly: AssemblyProduct("Space Automation Professional")]
[assembly: AssemblyCopyright("Copyright (c) 2013 - 2021 Blue Yonder Group, Inc.")]
[assembly: ComVisible(false)]
[assembly: Guid("your-project-guid-lowercase-no-braces")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
```

Guid must match the `<ProjectGuid>` in the `.csproj` (lowercase, no braces).

---

## Namespace and Class Name Rules

| Script Type | Namespace | Class Name |
|---|---|---|
| Space Planning (planograms) | `SpaceMenuAssembly` | `SpaceMenuClass` |
| Floor Planning (floorplans) | `FloorMenuAssembly` | `FloorMenuClass` |

Both class names are **fixed** — the SA Pro engine discovers them by these exact names.

---

## Script Class Boilerplate

```csharp
#region
using JDA.Intactix.Automation;
using JDA.Intactix.DataAccess.Common;
using JDA.Intactix.IKB.DataAccess;

using SpaceMenuAssembly.HelperClasses;   // or FloorMenuAssembly.HelperClasses

using Serilog.Core;

using System;
using System.Data;
using System.Diagnostics;
using System.IO;

using Space = JDA.Intactix.Automation.Space;   // Space Planning
// using Floor = JDA.Intactix.Automation.Floor; // Floor Planning
#endregion

namespace SpaceMenuAssembly   // or FloorMenuAssembly
{
    [Serializable]
    public class SpaceMenuClass : Script   // or FloorMenuClass
    {
        public SpaceMenuClass()
            : base(0)
        {
        }

        public SpaceMenuClass(int nSpaceOrFloor)
            : base(nSpaceOrFloor)
        {
        }

        public override void Run(bool isSilentMode = true)
        {
            System.Diagnostics.Debugger.Launch();   // attach JIT debugger

            Logger logger = ConfigurationHelper.CreateLogger();
            logger.Information("Starting Run()");

            try
            {
                // read config, build dependencies, run logic
            }
            catch (Exception ex)
            {
                logger.Error(ex, "Run Exception");
                throw;
            }

            logger.Information("Finished Run()");
        }
    }
}
```

---

## FloorPlanning API Gap

`FloorPlanning` does **not** expose `GetObjectCount()`. Do not call it.
To safely close any open project before starting:

```csharp
// Safe — silently ignored if nothing is open
try { FloorPlanning.CloseProjectFile(); } catch { }
```

`SpacePlanning.GetObjectCount("Project")` is available and should be used normally:

```csharp
if (SpacePlanning.GetObjectCount("Project") > 0)
{
    SpacePlanning.CloseProjectFile();
}
```

---

## Adding the Project to the Solution

After creating the project files, add it to your solution file (`.slnx` or `.sln`).

For `.slnx` format:
```xml
<Project Path="ScriptName/ScriptName/ScriptName.csproj" Id="your-guid-here" />
```

The `Id` attribute uses lowercase GUID without braces.
