---
name: crisp-csharp-style
description: >
  Generate, review, and debug C# code following the Crisp/Blue Yonder JDA Space Automation
  coding conventions. Use this skill whenever writing new C# scripts or class libraries for
  JDA Space Automation Pro, CKB (Category Knowledge Base), or related tooling. Covers project
  structure, Dapper database access, Serilog RollingFileAlternate logging, and the exact
  method/class patterns established in the Blackhawk ProductExport and SampleSpaceBRV template
  projects. Trigger any time the user asks to write, scaffold, or review C# code for these systems.
---

# Crisp C# Coding Style Skill

You generate and review C# code that strictly follows the coding conventions established in the
Blackhawk ProductExport project and the CrispCKBTechnicalTemplates SampleSpaceBRV template.

---

## Reference Files

Read these before writing any code:

- **`references/project-structure.md`** — Folder layout, .csproj setup, NuGet packages, namespace
  conventions. Read first when scaffolding a new project.
- **`references/coding-style.md`** — Class structure, field naming, constructor patterns, method
  signatures, models, error handling. Read for any code generation task.
- **`references/serilog-patterns.md`** — Exact Serilog RollingFileAlternate setup and usage.
  Every method must log Start/Finish with try/catch.
- **`references/dapper-patterns.md`** — Dapper connection management, DynamicParameters, stored
  procedure calls, ExecuteReader → DataTable, ExecuteScalar.
- **`references/wpf-patterns.md`** — WPF Window/code-behind boilerplate, event handler pattern,
  DataGrid binding, file dialogs. Read any time a UI is needed.

---

## Core Rules (Non-Negotiable)

### 1. Every Method Has Start/Finish Logging + Try/Catch

```csharp
internal DataTable GetSomeData(string parameter)
{
    _logger.Information($"Starting GetSomeData()");

    var retVal = new DataTable();

    try
    {
        // ... implementation ...
    }
    catch (Exception ex)
    {
        _logger.Error(ex, "GetSomeData Exception");
    }

    _logger.Information($"Finished GetSomeData() - retVal: {retVal.Rows.Count} rows");
    return retVal;
}
```

- `_logger.Information($"Starting MethodName()")` is the FIRST line of every method body.
- `_logger.Information($"Finished MethodName()")` is immediately before the return.
- All logic lives inside `try { }`.
- `catch (Exception ex)` logs with `_logger.Error(ex, "MethodName Exception")`.
- Never swallow exceptions silently — always log.

### 2. Private Fields Use Underscore Prefix

```csharp
private readonly IKBDbSupport _support;
private readonly Logger _logger;
private SqlConnection _connectionString;
private readonly string _customSchema;
```

### 3. Dapper for All Database Calls

Use `GetDbConnection()` / `ConnectionCleanup()` pattern. Never leave connections open.
Use `DynamicParameters` for stored procedures. See `references/dapper-patterns.md`.

### 4. Serilog with RollingFileAlternate

Logger is `Serilog.Core.Logger` (not `ILogger`). Set up once in `ConfigurationHelper`.
See `references/serilog-patterns.md` for exact configuration.

### 5. UI = WPF, Not Windows Forms

If any UI is required, use **WPF** (Windows Presentation Foundation):
- Windows live in a `Views\` folder: `MainWindow.xaml` + `MainWindow.xaml.cs`.
- Use code-behind — no MVVM, no ViewModels, no binding frameworks.
- Pass `CommandFactory` and `Logger` into Window constructors.
- Every event handler follows the same Start/Finish logging + try/catch pattern.
- Use `System.Windows.MessageBox` (not `System.Windows.Forms`).
- See `references/wpf-patterns.md` for full boilerplate and rules.

### 6. Folder and Namespace Structure

Follow the SampleSpaceBRV layout exactly:
- `HelperClasses/` — CommandFactory, ConfigurationHelper, CommonConstants
- `Models/` — simple POCOs, auto-properties only
- `SQL/Stored Procedures/`, `SQL/Tables/`, `SQL/Views/` — SQL scripts
- `Libraries/` — local JDA DLL references

See `references/project-structure.md`.

---

## What You Do

### Scaffold a New Project
1. Read `references/project-structure.md`.
2. Output the folder tree, .csproj NuGet packages, and boilerplate files:
   - Main script class (inherits `Script`)
   - `ConfigurationHelper.cs`
   - `CommandFactory.cs` (empty, ready for stored proc methods)
   - `CommonConstants.cs` (empty shell)
   - A sample model
3. If the user mentions a UI, also read `references/wpf-patterns.md` and add:
   - `Views\MainWindow.xaml` and `Views\MainWindow.xaml.cs`
   - WPF assembly references in .csproj
   - Window launch code in `Run()`

### Write a WPF Window
1. Read `references/wpf-patterns.md`.
2. Scaffold `MainWindow.xaml` (layout) and `MainWindow.xaml.cs` (code-behind).
3. Constructor accepts `CommandFactory` and `Logger` — never instantiates them.
4. All click handlers follow Start/Finish logging + try/catch.
5. Data displayed via `DataGrid` bound to `DataTable.DefaultView`.

### Write a New CommandFactory Method
1. Read `references/dapper-patterns.md` and `references/serilog-patterns.md`.
2. Write the method with Start/Finish logging, try/catch, DynamicParameters, stored proc call.
3. Return `DataTable`, `string`, `bool`, or `List<T>` — match the pattern for the return type.

### Review Existing Code
- Flag: missing Start/Finish logging, missing try/catch, bare SQL strings (prefer stored procs),
  unclosed connections, async/await (not used in this style), `ILogger` instead of `Logger`.
- Suggest: correct Dapper pattern, connection cleanup, Serilog call format.

### Add a New Model
- Simple POCO in `Models/` folder.
- Only auto-properties: `public string Name { get; set; }`
- `internal` visibility unless cross-assembly.
- No constructor logic.

---

## Output Format

- **New files**: Full C# file content with correct `using` block wrapped in `#region` / `#endregion`.
- **Methods**: Standalone method blocks ready to paste into `CommandFactory`.
- **Reviews**: Bulleted list of issues, then corrected code.
- Always match the namespace to the project being worked on — ask if unknown.
