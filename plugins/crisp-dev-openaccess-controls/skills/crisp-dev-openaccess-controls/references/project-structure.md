# OA Control Project Structure

Every OA control project is a **WebApplication** (OutputType: Library). Use the templates
below to scaffold a new project from scratch. `SampleOAProject` is kept in the solution as
the authoritative source for the `Libraries\` DLLs — copy from `SampleOAProject\Libraries\`
into the new project's `Libraries\` folder.

---

## Folder Layout

```
MyControl\
  MyControl.csproj
  CopyWebUI.bat
  Web.config
  packages.config
  Libraries\               ← copy from SampleOAProject\Libraries\
  Config\
    CrispCustomizations.config
  CSS\
    MyControl.css
  Javascript\
    MyControl.js
  Views\
    MyControlUI.ascx
    MyControlUI.ascx.cs
    MyControlUI.ascx.designer.cs
  DerivedGrid\             ← only for derived controls
    CXMyControlGrid.cs
  HelperClasses\
    CommandFactory.cs
    ConfigurationHelper.cs
  Models\
    MyControlModel.cs
  Properties\
    AssemblyInfo.cs
  SQL\
    Stored Procedures\
    Tables\
```

---

## .csproj Template

```xml
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Import Project="..\packages\Microsoft.CodeDom.Providers.DotNetCompilerPlatform.2.0.1\build\net46\Microsoft.CodeDom.Providers.DotNetCompilerPlatform.props"
          Condition="Exists('..\packages\Microsoft.CodeDom.Providers.DotNetCompilerPlatform.2.0.1\build\net46\Microsoft.CodeDom.Providers.DotNetCompilerPlatform.props')" />
  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props"
          Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
  <PropertyGroup>
    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
    <ProjectGuid>{NEW-GUID-HERE}</ProjectGuid>
    <ProjectTypeGuids>{349c5851-65df-11da-9384-00065b846f21};{fae04ec0-301f-11d3-bf4b-00c04f79efbc}</ProjectTypeGuids>
    <OutputType>Library</OutputType>
    <AppDesignerFolder>Properties</AppDesignerFolder>
    <RootNamespace>MyControl</RootNamespace>
    <AssemblyName>MyControl</AssemblyName>
    <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
    <UseIISExpress>true</UseIISExpress>
  </PropertyGroup>
  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
    <DebugSymbols>true</DebugSymbols>
    <DebugType>full</DebugType>
    <Optimize>false</Optimize>
    <OutputPath>bin\</OutputPath>
    <DefineConstants>DEBUG;TRACE</DefineConstants>
    <ErrorReport>prompt</ErrorReport>
    <WarningLevel>4</WarningLevel>
  </PropertyGroup>
  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
    <DebugType>pdbonly</DebugType>
    <Optimize>true</Optimize>
    <OutputPath>bin\</OutputPath>
    <DefineConstants>TRACE</DefineConstants>
    <ErrorReport>prompt</ErrorReport>
    <WarningLevel>4</WarningLevel>
  </PropertyGroup>
  <ItemGroup>
    <!-- NuGet packages -->
    <Reference Include="Dapper, Version=2.0.0.0, Culture=neutral, processorArchitecture=MSIL">
      <HintPath>..\packages\Dapper.2.1.35\lib\net461\Dapper.dll</HintPath>
    </Reference>
    <Reference Include="Serilog">
      <HintPath>..\packages\Serilog.3.1.1\lib\net471\Serilog.dll</HintPath>
    </Reference>
    <Reference Include="Serilog.Sinks.RollingFileAlternate">
      <HintPath>..\packages\Serilog.Sinks.RollingFileAlternate.2.0.9\lib\net451\Serilog.Sinks.RollingFileAlternate.dll</HintPath>
    </Reference>
    <!-- JDA OA DLLs from Libraries\ -->
    <Reference Include="JDA.Intactix.Common, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.Common.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.Configuration, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.Configuration.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.DataAccess, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.DataAccess.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.IKB.Common, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.IKB.Common.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.IKB.DataAccess, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.IKB.DataAccess.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.IKB.Support, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.IKB.Support.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.IKB.Web, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.IKB.Web.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.IKB.Web.Common, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.IKB.Web.Common.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.IKB.Web.Framework, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.IKB.Web.Framework.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.IKB.Web.UI, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.IKB.Web.UI.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.IKB.Web.UI.WebControls, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.IKB.Web.UI.WebControls.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.Web.Common, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.Web.Common.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.Web.Framework, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.Web.Framework.dll</HintPath>
    </Reference>
    <Reference Include="JDA.Intactix.Web.UI.WebControls, Version=2024.4.0.98, Culture=neutral, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\JDA.Intactix.Web.UI.WebControls.dll</HintPath>
    </Reference>
    <Reference Include="Microsoft.CSharp" />
    <Reference Include="Microsoft.CodeDom.Providers.DotNetCompilerPlatform">
      <HintPath>..\packages\Microsoft.CodeDom.Providers.DotNetCompilerPlatform.2.0.1\lib\net45\Microsoft.CodeDom.Providers.DotNetCompilerPlatform.dll</HintPath>
    </Reference>
    <Reference Include="Newtonsoft.Json, Version=13.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed, processorArchitecture=MSIL">
      <SpecificVersion>False</SpecificVersion>
      <HintPath>Libraries\Newtonsoft.Json.dll</HintPath>
    </Reference>
    <Reference Include="System" />
    <Reference Include="System.Configuration" />
    <Reference Include="System.Data" />
    <Reference Include="System.Data.DataSetExtensions" />
    <Reference Include="System.Web" />
    <Reference Include="System.Web.Extensions" />
    <Reference Include="System.Xml" />
    <Reference Include="System.Xml.Linq" />
  </ItemGroup>
  <ItemGroup>
    <!-- Add one <Compile> per .cs file -->
    <Compile Include="HelperClasses\CommandFactory.cs" />
    <Compile Include="HelperClasses\ConfigurationHelper.cs" />
    <Compile Include="Models\MyControlModel.cs" />
    <Compile Include="Properties\AssemblyInfo.cs" />
    <Compile Include="Views\MyControlUI.ascx.cs">
      <DependentUpon>MyControlUI.ascx</DependentUpon>
      <SubType>ASPXCodeBehind</SubType>
    </Compile>
    <Compile Include="Views\MyControlUI.ascx.designer.cs">
      <DependentUpon>MyControlUI.ascx</DependentUpon>
    </Compile>
  </ItemGroup>
  <ItemGroup>
    <Content Include="Config\CrispCustomizations.config" />
    <Content Include="CopyWebUI.bat" />
    <!-- List all 14 JDA DLLs + Newtonsoft as Content so VS shows them -->
    <Content Include="Libraries\JDA.Intactix.Common.dll" />
    <Content Include="Libraries\JDA.Intactix.Configuration.dll" />
    <Content Include="Libraries\JDA.Intactix.DataAccess.dll" />
    <Content Include="Libraries\JDA.Intactix.IKB.Common.dll" />
    <Content Include="Libraries\JDA.Intactix.IKB.DataAccess.dll" />
    <Content Include="Libraries\JDA.Intactix.IKB.Support.dll" />
    <Content Include="Libraries\JDA.Intactix.IKB.Web.Common.dll" />
    <Content Include="Libraries\JDA.Intactix.IKB.Web.dll" />
    <Content Include="Libraries\JDA.Intactix.IKB.Web.Framework.dll" />
    <Content Include="Libraries\JDA.Intactix.IKB.Web.UI.dll" />
    <Content Include="Libraries\JDA.Intactix.IKB.Web.UI.WebControls.dll" />
    <Content Include="Libraries\JDA.Intactix.Web.Common.dll" />
    <Content Include="Libraries\JDA.Intactix.Web.Framework.dll" />
    <Content Include="Libraries\JDA.Intactix.Web.UI.WebControls.dll" />
    <Content Include="Libraries\Newtonsoft.Json.dll" />
    <Content Include="Views\MyControlUI.ascx" />
    <Content Include="Web.config" />
  </ItemGroup>
  <ItemGroup>
    <None Include="packages.config" />
  </ItemGroup>
  <ItemGroup>
    <Folder Include="SQL\Stored Procedures\" />
    <Folder Include="SQL\Tables\" />
  </ItemGroup>
  <PropertyGroup>
    <VisualStudioVersion Condition="'$(VisualStudioVersion)' == ''">10.0</VisualStudioVersion>
    <VSToolsPath Condition="'$(VSToolsPath)' == ''">$(MSBuildExtensionsPath32)\Microsoft\VisualStudio\v$(VisualStudioVersion)</VSToolsPath>
  </PropertyGroup>
  <Import Project="$(MSBuildBinPath)\Microsoft.CSharp.targets" />
  <Import Project="$(VSToolsPath)\WebApplications\Microsoft.WebApplication.targets" Condition="'$(VSToolsPath)' != ''" />
  <PropertyGroup>
    <PostBuildEvent>"$(ProjectDir)CopyWebUI.bat" "$(ProjectDir)"</PostBuildEvent>
  </PropertyGroup>
</Project>
```

---

## Libraries Setup

Copy from the sample OA project's `Libraries\` folder — this project is kept in the solution and source control specifically so this folder is always available. Ask the user for the name of their sample project if you don't know it (common names: `SampleOAProject`, `OADerivedControls`, etc.).

```
xcopy /Y "$(SolutionDir)[SampleProjectName]\Libraries\*" "MyControl\Libraries\"
```

Required DLLs (all 15):
```
JDA.Intactix.Common.dll
JDA.Intactix.Configuration.dll
JDA.Intactix.DataAccess.dll
JDA.Intactix.IKB.Common.dll
JDA.Intactix.IKB.DataAccess.dll
JDA.Intactix.IKB.Support.dll
JDA.Intactix.IKB.Web.Common.dll
JDA.Intactix.IKB.Web.dll
JDA.Intactix.IKB.Web.Framework.dll
JDA.Intactix.IKB.Web.UI.dll
JDA.Intactix.IKB.Web.UI.WebControls.dll
JDA.Intactix.Web.Common.dll
JDA.Intactix.Web.Framework.dll
JDA.Intactix.Web.UI.WebControls.dll
Newtonsoft.Json.dll
```

---

## CopyWebUI.bat

```bat
exit 0
SET PROJECT_DIR=%~1%

SET WEB_APPLICATION_DIR=C:\Program Files (x86)\JDA\Intactix\Intactix Knowledge Base\Open Access

if not exist "%WEB_APPLICATION_DIR%\Custom"         mkdir "%WEB_APPLICATION_DIR%\Custom"
if not exist "%WEB_APPLICATION_DIR%\Custom\Config"  mkdir "%WEB_APPLICATION_DIR%\Custom\Config"
if not exist "%WEB_APPLICATION_DIR%\Custom\Styles"  mkdir "%WEB_APPLICATION_DIR%\Custom\Styles"
if not exist "%WEB_APPLICATION_DIR%\Custom\scripts" mkdir "%WEB_APPLICATION_DIR%\Custom\scripts"

copy "%PROJECT_DIR%Views\*.ascx"                         "%WEB_APPLICATION_DIR%\Custom"
copy "%PROJECT_DIR%bin\MyControl.dll"                    "%WEB_APPLICATION_DIR%\bin"
copy "%PROJECT_DIR%CSS\MyControl.css"                    "%WEB_APPLICATION_DIR%\Custom\Styles"
copy "%PROJECT_DIR%Javascript\MyControl.js"              "%WEB_APPLICATION_DIR%\Custom\scripts"
copy "%PROJECT_DIR%Config\CrispCustomizations.config"    "%WEB_APPLICATION_DIR%\Custom\Config"
```

`exit 0` on line 1 disables the script on machines without OA installed. Comment it out on dev machines.

---

## Config\CrispCustomizations.config

```xml
<?xml version="1.0"?>
<configuration>
  <appSettings>
    <add key="CustomSchema" value="[your_schema]" />
    <add key="IsDebugging"  value="true" />
  </appSettings>
</configuration>
```

---

## packages.config

Copy `SampleOAProject\packages.config` verbatim. It pins the exact versions already
downloaded into `$(SolutionDir)packages\` and shared across all OA projects in the solution.

---

## Web.config

Copy `SampleOAProject\Web.config` verbatim. It contains the assembly binding redirects
required by Serilog, DocumentFormat.OpenXml, and other transitive dependencies.

---

## Properties\AssemblyInfo.cs

```csharp
using System.Reflection;

[assembly: AssemblyTitle("MyControl")]
[assembly: AssemblyDescription("")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
```

---

## Add to solution

```xml
<Project Path="MyControl/MyControl.csproj" Id="{NEW-GUID-HERE}" />
```

Generate a fresh GUID for each new project. The GUID must also appear in the `.csproj`
`<ProjectGuid>` element.
