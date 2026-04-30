# C# Coding Style Reference

Based on Blackhawk\ProductExport and CrispCKBTechnicalTemplates\SampleSpaceBRV.

---

## Field Naming

```csharp
// Private fields: underscore + camelCase
private readonly IKBDbSupport _support;
private readonly Logger _logger;
private SqlConnection _connectionString;
private readonly string _customSchema;
private CommandFactory _commandFactory;

// Constants: PascalCase
private const int CommandTimeoutSeconds = 600;
internal const string CKB_Table_Products = "ix_spc_product";

// Public properties on models: PascalCase auto-props only
public string Name { get; set; }
public int DBKey { get; set; }
```

**Never**: `m_field`, `sField`, `strName`, Hungarian notation.

---

## Class Visibility

| Class Type | Visibility |
|------------|------------|
| Main script class | `public` |
| CommandFactory | `public` |
| ConfigurationHelper | `public static` |
| CommonConstants | `internal static` |
| Models | `internal` (unless cross-assembly) |

---

## Constructor Patterns

Always provide two overloads for the main script class.

- Space Planning scripts: class `SpaceMenuClass` in namespace `SpaceMenuAssembly`
- Floor Planning scripts: class `FloorMenuClass` in namespace `FloorMenuAssembly`

```csharp
// Space Planning
[Serializable]
public class SpaceMenuClass : Script
{
    public SpaceMenuClass()
        : base(0)
    {
    }

    public SpaceMenuClass(int nSpaceOrFloor)
        : base(nSpaceOrFloor)
    {
    }
}

// Floor Planning
[Serializable]
public class FloorMenuClass : Script
{
    public FloorMenuClass()
        : base(0)
    {
    }

    public FloorMenuClass(int nSpaceOrFloor)
        : base(nSpaceOrFloor)
    {
    }
}
```

CommandFactory constructor injection (manual — no DI container):

```csharp
public CommandFactory(IKBDbSupport support, string customSchema, Logger logger)
{
    _support = support;
    _customSchema = customSchema;
    _logger = logger;
}

// Overload without logger (for cases where logging not yet initialized)
public CommandFactory(IKBDbSupport support, string customSchema)
{
    _support = support;
    _customSchema = customSchema;
}
```

---

## Using Statement Block

Always wrap `using` statements in `#region` / `#endregion` at the top of the file:

```csharp
#region
using Dapper;
using JDA.Intactix.Automation;
using JDA.Intactix.IKB.DataAccess;
using MyProjectAssembly.HelperClasses;
using MyProjectAssembly.Models;
using Newtonsoft.Json;
using Serilog.Core;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.IO;
using Space = JDA.Intactix.Automation.Space;
#endregion
```

---

## Method Signatures

### Visibility

| Method type | Visibility |
|-------------|------------|
| CommandFactory DB methods | `internal` |
| Main script helpers | `private` |
| Static utility methods | `private static` or `public static` |
| Entry point | `public override` |

### No Async/Await

This codebase is **fully synchronous**. Never use `async`/`await`, `Task<T>`, or `.Result`/`.GetAwaiter()`.

### Parameter Naming

- Parameters to public/internal methods: PascalCase (`CKBTable`, `ExcelData`, `Report`)
- Parameters to private methods: camelCase (`tableName`, `inputData`)
- Inconsistency between these two conventions exists in the original — match it per method type.

### Return Types

- Prefer returning the value directly via a `retVal` local: declare it at the top, set it in try,
  return it at the bottom.
- Always initialize `retVal` before the try block:

```csharp
var retVal = new DataTable();   // DataTable
var retVal = string.Empty;       // string
var retVal = false;              // bool
var retVal = new List<string>(); // list
```

---

## Method Body Structure (Required)

See `serilog-patterns.md` for the exact start/finish/try/catch pattern.

Summary: **Every method** has:
1. `_logger.Information($"Starting MethodName()")` — first line
2. `retVal` declared
3. `try { }` wrapping all logic
4. `catch (Exception ex) { _logger.Error(ex, "MethodName Exception"); }`
5. `_logger.Information($"Finished MethodName() - retVal: {retVal}")` — last line before return

---

## Init() Pattern

Dependencies are wired manually in a private `Init()` method called from `Run()`. This separates
initialization logic from business logic and makes the code more maintainable.

### Instance Fields
Declare private fields at the class level to store initialized dependencies:

```csharp
private Logger _logger;
private string _archivePath;
private string _pogKeyFilePath;
private string _customSchema;
private CommandFactory _commandFactory;
```

### Init() Method
Create a private `Init()` method that:
- Creates the logger
- Loads configuration settings
- Sets up database connections
- Initializes the CommandFactory
- Validates and creates necessary directories
- Closes any open JDA projects

```csharp
private void Init()
{
    _logger = ConfigurationHelper.CreateLogger();
    _logger.Information("Initializing script");

    // Read all config keys your script needs from app.config
    _customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");
    // _mySettingA = ConfigurationHelper.GetConfigSetting("MySettingA");

    var dbSupport = new IKBDbSupport(
        "Category Knowledge Base",
        ConfigurationHelper.GetConfigSetting("ServerName"),
        ConfigurationHelper.GetConfigSetting("DatabaseName"),
        DbProviderType.SqlServer,
        600);

    _commandFactory = new CommandFactory(dbSupport, _customSchema, _logger);

    // Add any other initialization your script needs here:
    // - Validate required config values
    // - Create output directories
    // - Close any open JDA projects (if script requires a clean state)

    _logger.Information("Initialization complete");
}
```

### Run() Method
Call `Init()` at the start and use instance fields throughout:

```csharp
public override void Run(bool isSilentMode = true)
{
    Debugger.Launch();

    try
    {
        Init();

        _logger.Information("Starting Run()");

        // Script logic here — call CommandFactory methods, loop over data, etc.

        _logger.Information("Finished Run()");
    }
    catch (Exception ex)
    {
        _logger?.Error(ex, "Run Exception");
        throw;
    }
}
```

---

## JDA API Best Practices

### Use Direct Property Access, Not GetFieldValue()

The JDA API provides direct property access for all fields. **Always use properties instead of `GetFieldValue()`**.

**BAD:**
```csharp
var desc1 = pog.GetFieldValue("Desc 1").Trim();
var desc3 = pog.GetFieldValue("Desc 3").Trim();
var dateEffective = pog.GetFieldValue("Date Effective");
```

**GOOD:**
```csharp
var desc1 = pog.Desc1.Trim();
var desc3 = pog.Desc3.Trim();
var dateEffective = pog.DateEffective;
```

### JDA Field Defaults

The JDA API guarantees default values — no null-coalescing needed:
- **Description fields** (`Desc1`, `Desc2`, etc.) → Return empty string by default
- **Date/numeric fields** (`DateEffective`, `DateLive`, etc.) → Return `0` by default

**Do NOT use null-coalescing:**
```csharp
// BAD - unnecessary
var desc1 = pog.Desc1?.Trim() ?? string.Empty;

// GOOD - JDA API guarantees non-null
var desc1 = pog.Desc1.Trim();
```

### Date Field Handling

Date fields return `Double` (OLE Automation date format). Use `DateTime.FromOADate()` to convert:

```csharp
var dateEffective = pog.DateEffective;

if (dateEffective == 0)
{
    _logger.Warning($"Planogram {myKey} has invalid DateEffective");
    continue;
}

var formattedDate = DateTime.FromOADate(dateEffective).ToString("M/d/yyyy");
```

### Validation Pattern for JDA Objects

Always validate JDA objects and required fields before use:

```csharp
var pog = SpacePlanning.ActivePlanogram;

// 1. Null check
if (pog == null)
{
    _logger.Warning($"Planogram DBKey {myKey} is null after opening");
    continue;
}

// 2. Required string fields
if (string.IsNullOrWhiteSpace(pog.Name))
{
    _logger.Warning($"Planogram DBKey {myKey} has null or empty Name");
    SpacePlanning.CloseProjectFile();
    continue;
}

// 3. Required descriptor fields (for path building, etc.)
if (string.IsNullOrWhiteSpace(desc1) || string.IsNullOrWhiteSpace(desc3))
{
    _logger.Warning($"Planogram DBKey {myKey} has null or empty Desc1 or Desc3");
    SpacePlanning.CloseProjectFile();
    continue;
}

// 4. Date validation (0 = unset)
if (dateEffective == 0)
{
    _logger.Warning($"Planogram DBKey {myKey} has invalid DateEffective");
    SpacePlanning.CloseProjectFile();
    continue;
}
```

### Directory Validation

Always validate directories exist before operations:

```csharp
if (!Directory.Exists(archivePath))
{
    _logger.Warning($"Archive path does not exist: {archivePath}");
    Directory.CreateDirectory(archivePath);
    _logger.Information($"Created archive path: {archivePath}");
}

var thedirectory = Path.Combine(archivePath, desc1, desc3, desc5);

if (!Directory.Exists(thedirectory))
{
    Directory.CreateDirectory(thedirectory);
}
```

### Use `var` for Local Variables

Always use `var` for local variable declarations. This is modern C# best practice and used throughout the codebase.

**BAD:**
```csharp
DataTable keysTable = _commandFactory.GetToBePurgedPOGKeys();
string desc1 = pog.Desc1.Trim();
Space.Planogram pog = SpacePlanning.ActivePlanogram;
```

**GOOD:**
```csharp
var keysTable = _commandFactory.GetToBePurgedPOGKeys();
var desc1 = pog.Desc1.Trim();
var pog = SpacePlanning.ActivePlanogram;
```

**Exception:** Keep explicit types for private fields and method signatures for clarity.

---

## Model Classes

```csharp
// Models\ProductModel.cs
namespace MyProjectAssembly.Models
{
    internal class ProductModel
    {
        public int DBKey { get; set; }
        public string ProductName { get; set; }
        public string UPC { get; set; }
        public decimal TDV { get; set; }
        public int TotalFacings { get; set; }
    }
}
```

Rules:
- Auto-properties only — no backing fields.
- `internal` visibility.
- No constructors, no methods — pure data containers.
- Match property names to column names where possible (Dapper maps by name).
- One model per file, file name matches class name.

---

## Error Handling Levels

### In CommandFactory (data layer)

```csharp
catch (Exception ex)
{
    _logger.Error(ex, "MethodName Exception");
    // Do NOT rethrow — return empty/default retVal
}
```

### In main script class (orchestration layer)

```csharp
catch (Exception ex)
{
    _logger.Error(ex, "MethodName Exception");
    throw;  // Rethrow so JDA script engine sees the failure
}
```

### Specific exception types (use when meaningful)

```csharp
catch (TimeoutException tex)
{
    _logger.Error(tex, "GetData Timeout");
    // handle timeout-specific recovery
}
catch (Exception ex)
{
    _logger.Error(ex, "GetData Exception");
}
```

---

## Inline Comments

- Block comments for logical sections within a method.
- No XML doc comments (`///`) except on public-facing classes.
- Comment why, not what:

```csharp
// Remove the key column before sending to validation — it's not part of the schema check
ExcelData.Columns.RemoveAt(0);
```

---

## String Interpolation vs Concatenation

Always use `$""` interpolation:

```csharp
// Good
_logger.Information($"Starting GetData() - table: {tableName}");
var sp = $"{_customSchema}.cx_product_data_get";

// Avoid
_logger.Information("Starting GetData() - table: " + tableName);
```

---

## What NOT to Do

```csharp
// No async/await
public async Task<DataTable> GetDataAsync() { }

// No Entity Framework
var items = _context.Products.ToList();

// No ILogger<T> (ASP.NET Core style)
private readonly ILogger<CommandFactory> _logger;

// No auto-wired DI container
[Inject]
private IKBDbSupport _support;

// No public fields on models
public class ProductModel { public string Name; }  // should be { get; set; }

// No swallowed exceptions
catch (Exception) { }

// No hardcoded schema
conn.ExecuteReader("ckbcustom.cx_product_get", ...);

// No LINQ on database results when Dapper can do it
.Where(x => x.Status == 1).ToList()  // prefer SQL filter in stored proc
```
