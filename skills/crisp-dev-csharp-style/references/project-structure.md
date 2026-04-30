# Project Structure Reference

Based on CrispCKBTechnicalTemplates\SampleBRV\SampleSpaceBRV.

---

## Folder Layout

```
MyProjectName\
├── HelperClasses\
│   ├── CommandFactory.cs       ← all DB operations via Dapper
│   ├── CommonConstants.cs      ← static string constants (table names, SP names, etc.)
│   └── ConfigurationHelper.cs  ← reads app.config, creates Serilog logger
├── Libraries\                  ← local JDA DLL references (not in NuGet)
├── Models\
│   └── SampleModel.cs          ← POCOs / DTOs
├── Properties\
│   └── AssemblyInfo.cs
├── SQL\
│   ├── Stored Procedures\      ← .sql files for every stored proc used
│   ├── Tables\
│   ├── Types\
│   └── Views\
├── MyProject.cs                ← main script class (inherits Script), root level
├── MyProject.csproj
├── app.config                  ← assembly binding redirects + appSettings keys
├── appSettings.json            ← identity / service endpoint config (if needed)
└── packages.config
```

---

## .csproj Key Properties

```xml
<PropertyGroup>
  <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
  <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
  <ProductVersion>8.0.30703</ProductVersion>
  <SchemaVersion>2.0</SchemaVersion>
  <OutputType>Library</OutputType>
  <AppDesignerFolder>Properties</AppDesignerFolder>
  <RootNamespace>MyProjectAssembly</RootNamespace>
  <AssemblyName>MyProject</AssemblyName>
  <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
  <ToolsVersion>12.0</ToolsVersion>
</PropertyGroup>
```

---

## Required NuGet Packages (packages.config)

```xml
<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="Dapper" version="2.1.35" targetFramework="net48" />
  <package id="Microsoft.Bcl.AsyncInterfaces" version="8.0.0" targetFramework="net48" />
  <package id="Microsoft.Extensions.Configuration.Abstractions" version="8.0.0" targetFramework="net48" />
  <package id="Microsoft.Extensions.Configuration.Binder" version="8.0.0" targetFramework="net48" />
  <package id="Microsoft.Extensions.DependencyModel" version="8.0.0" targetFramework="net48" />
  <package id="Microsoft.Extensions.Primitives" version="8.0.0" targetFramework="net48" />
  <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net48" />
  <package id="Serilog" version="3.1.1" targetFramework="net48" />
  <package id="Serilog.Settings.Configuration" version="8.0.0" targetFramework="net48" />
  <package id="Serilog.Sinks.RollingFileAlternate" version="2.0.9" targetFramework="net48" />
  <package id="System.Buffers" version="4.5.1" targetFramework="net48" />
  <package id="System.Memory" version="4.5.5" targetFramework="net48" />
  <package id="System.Numerics.Vectors" version="4.5.0" targetFramework="net48" />
  <package id="System.Runtime.CompilerServices.Unsafe" version="6.0.0" targetFramework="net48" />
  <package id="System.Text.Encodings.Web" version="8.0.0" targetFramework="net48" />
  <package id="System.Text.Json" version="8.0.0" targetFramework="net48" />
  <package id="System.Threading.Tasks.Extensions" version="4.5.4" targetFramework="net48" />
  <package id="System.ValueTuple" version="4.5.0" targetFramework="net48" />
</packages>
```

---

## Standard Assembly References (csproj)

```xml
<ItemGroup>
  <Reference Include="Microsoft.CSharp" />
  <Reference Include="System" />
  <Reference Include="System.Configuration" />
  <Reference Include="System.Core" />
  <Reference Include="System.Data" />
  <Reference Include="System.Data.DataSetExtensions" />
  <Reference Include="System.Numerics" />
  <Reference Include="System.Runtime" />
  <Reference Include="System.Xml" />
  <Reference Include="System.Xml.Linq" />
</ItemGroup>
```

## JDA DLL References (from local Libraries\ folder)

```xml
<ItemGroup>
  <Reference Include="JDA.Intactix.Automation">
    <HintPath>Libraries\JDA.Intactix.Automation.dll</HintPath>
  </Reference>
  <Reference Include="JDA.Intactix.IKB.DataAccess">
    <HintPath>Libraries\JDA.Intactix.IKB.DataAccess.dll</HintPath>
  </Reference>
  <!-- Add others as needed from Libraries\ -->
</ItemGroup>
```

---

## Namespace Conventions

| Folder | Namespace |
|--------|-----------|
| Root (main script class) | `SpaceMenuAssembly` (Space Planning) or `FloorMenuAssembly` (Floor Planning) |
| HelperClasses\ | `SpaceMenuAssembly.HelperClasses` or `FloorMenuAssembly.HelperClasses` |
| Models\ | `SpaceMenuAssembly.Models` or `FloorMenuAssembly.Models` |

- Space Planning scripts always use namespace `SpaceMenuAssembly`, class `SpaceMenuClass`.
- Floor Planning scripts always use namespace `FloorMenuAssembly`, class `FloorMenuClass`.
- `RootNamespace` in .csproj matches the root script class namespace.
- Helper/model namespaces always append `.HelperClasses` or `.Models`.

---

## Main Script Class Boilerplate

### Space Planning (SpaceMenu.cs)

```csharp
#region
using JDA.Intactix.Automation;

using SpaceMenuAssembly.HelperClasses;

using Serilog.Core;

using System;
using System.Collections.Generic;
using System.Text;

using Space = JDA.Intactix.Automation.Space;
#endregion

namespace SpaceMenuAssembly
{
    [Serializable]
    public class SpaceMenuClass : Script
    {
        private CommandFactory _commandFactory;
        private Logger _logger;
        private string _customSchema;

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
            Init();
            // Script logic goes here
        }

        private void Init()
        {
            _logger = ConfigurationHelper.CreateLogger();
            _customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");

            var dbSupport = new JDA.Intactix.IKB.DataAccess.IKBDbSupport(
                "Category Knowledge Base",
                ConfigurationHelper.GetConfigSetting("ServerName"),
                ConfigurationHelper.GetConfigSetting("DatabaseName"),
                JDA.Intactix.DataAccess.Common.DbProviderType.SqlServer,
                600);

            _commandFactory = new CommandFactory(dbSupport, _customSchema, _logger);
        }
    }
}
```

### Floor Planning (FloorMenu.cs)

```csharp
#region
using JDA.Intactix.Automation;

using FloorMenuAssembly.HelperClasses;

using Serilog.Core;

using System;
using System.Collections.Generic;
using System.Text;

using Floor = JDA.Intactix.Automation.Floor;
#endregion

namespace FloorMenuAssembly
{
    [Serializable]
    public class FloorMenuClass : Script
    {
        private CommandFactory _commandFactory;
        private Logger _logger;
        private string _customSchema;

        public FloorMenuClass()
            : base(0)
        {
        }

        public FloorMenuClass(int nSpaceOrFloor)
            : base(nSpaceOrFloor)
        {
        }

        public override void Run(bool isSilentMode = true)
        {
            Init();
            // Script logic goes here
        }

        private void Init()
        {
            _logger = ConfigurationHelper.CreateLogger();
            _customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");

            var dbSupport = new JDA.Intactix.IKB.DataAccess.IKBDbSupport(
                "Category Knowledge Base",
                ConfigurationHelper.GetConfigSetting("ServerName"),
                ConfigurationHelper.GetConfigSetting("DatabaseName"),
                JDA.Intactix.DataAccess.Common.DbProviderType.SqlServer,
                600);

            _commandFactory = new CommandFactory(dbSupport, _customSchema, _logger);
        }
    }
}
```

---

## app.config Boilerplate

```xml
<?xml version="1.0" encoding="utf-8" ?>
<configuration>
  <appSettings>
    <add key="LogDirectory" value="C:\Logs\MyProject" />
    <add key="CustomSchema" value="[your_schema]" />
    <add key="DatabaseName" value="[your_database]" />
  </appSettings>
  <runtime>
    <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
      <dependentAssembly>
        <assemblyIdentity name="System.Runtime.CompilerServices.Unsafe"
                          publicKeyToken="b03f5f7f11d50a3a" culture="neutral" />
        <bindingRedirect oldVersion="0.0.0.0-6.0.0.0" newVersion="6.0.0.0" />
      </dependentAssembly>
    </assemblyBinding>
  </runtime>
</configuration>
```
