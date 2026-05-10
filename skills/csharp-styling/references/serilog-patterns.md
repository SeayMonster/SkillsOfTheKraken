# Serilog Patterns Reference

Based on SampleSpaceBRV\HelperClasses\ConfigurationHelper.cs.

---

## NuGet Packages Required

```
Serilog 3.1.1
Serilog.Sinks.RollingFileAlternate 2.0.9
Serilog.Settings.Configuration 8.0.0
```

---

## Logger Type

Always use `Serilog.Core.Logger` (the concrete type), **not** `ILogger` or `Serilog.ILogger`.

```csharp
using Serilog.Core;

private readonly Logger _logger;
```

---

## ConfigurationHelper.cs (Complete File)

```csharp
#region
using Serilog;
using Serilog.Core;
using Serilog.Sinks.RollingFileAlternate;

using System;
using System.Configuration;
using System.IO;
using System.Reflection;
#endregion

namespace MyProjectAssembly.HelperClasses
{
    /// <summary>
    /// Helper for reading configuration values from the executing assembly's config file
    /// and for creating the Serilog logger.
    /// </summary>
    public static class ConfigurationHelper
    {
        private static readonly string LogDirectory = GetConfigSetting("LogDirectory");

        public static Logger CreateLogger()
        {
            if (!Directory.Exists(LogDirectory))
            {
                Directory.CreateDirectory(LogDirectory);
            }

            return new LoggerConfiguration()
                .WriteTo.RollingFileAlternate(
                    LogDirectory,
                    logFilePrefix: $"{Environment.UserName?.Replace('\\', '-') ?? "UnknownUser"}",
                    minimumLevel: Serilog.Events.LogEventLevel.Debug,
                    outputTemplate: "{Timestamp:MM-dd-yyyy HH:mm:ss} [{Level}] {Message}{NewLine}{Exception}",
                    fileSizeLimitBytes: 1048576 / 8,
                    retainedFileCountLimit: 1)
                .CreateLogger();
        }

        public static string GetConfigSetting(string settingName)
        {
            try
            {
                string exePath = Assembly.GetExecutingAssembly().Location;
                string configPath = $"{exePath}.config";

                if (!File.Exists(configPath))
                {
                    return null;
                }

                var fileMap = new ExeConfigurationFileMap
                {
                    ExeConfigFilename = configPath
                };

                Configuration configuration = ConfigurationManager.OpenMappedExeConfiguration(
                    fileMap, ConfigurationUserLevel.None);
                AppSettingsSection appSettings = configuration.GetSection("appSettings") as AppSettingsSection;

                if (appSettings != null && appSettings.Settings[settingName] != null)
                {
                    return appSettings.Settings[settingName].Value;
                }

                return null;
            }
            catch (ConfigurationErrorsException)
            {
                return null;
            }
        }
    }
}
```

---

## Logger Creation (in main script class Init())

```csharp
private Logger _logger;

private void Init()
{
    _logger = ConfigurationHelper.CreateLogger();
    // ... rest of init
}
```

---

## RollingFileAlternate Configuration Details

| Parameter | Value | Notes |
|-----------|-------|-------|
| `LogDirectory` | From app.config `LogDirectory` key | Created if missing |
| `logFilePrefix` | `Environment.UserName` with `\` replaced by `-` | Falls back to `"UnknownUser"` |
| `minimumLevel` | `LogEventLevel.Debug` | Captures all levels |
| `outputTemplate` | `"{Timestamp:MM-dd-yyyy HH:mm:ss} [{Level}] {Message}{NewLine}{Exception}"` | Date, level, message, exception |
| `fileSizeLimitBytes` | `1048576 / 8` (128 KB) | Rolls to new file at this size |
| `retainedFileCountLimit` | `1` | Keeps only the current file |

---

## Method Logging Pattern (Required in Every Method)

Every method body must follow this exact structure:

```csharp
internal ReturnType MethodName(ParamType param)
{
    _logger.Information($"Starting MethodName()");

    var retVal = default(ReturnType);  // or new DataTable(), string.Empty, false, etc.

    try
    {
        // all logic here
    }
    catch (Exception ex)
    {
        _logger.Error(ex, "MethodName Exception");
    }

    _logger.Information($"Finished MethodName() - retVal: {retVal}");
    return retVal;
}
```

### Logging Return Values

| Return Type | Finish log pattern |
|-------------|-------------------|
| `DataTable` | `$"Finished X() - retVal: {retVal.Rows.Count} rows"` |
| `string` | `$"Finished X() - retVal: {retVal}"` |
| `bool` | `$"Finished X() - retVal: {retVal}"` |
| `List<T>` | `$"Finished X() - retVal: {retVal.Count} items"` |
| `void` | `_logger.Information($"Finished X()")` (no retVal) |

---

## Log Levels

| Method | When to use |
|--------|------------|
| `_logger.Information(message)` | Normal flow: start, finish, progress milestones |
| `_logger.Warning(message)` | Non-fatal issues: config key missing, unexpected empty result |
| `_logger.Error(ex, message)` | Exception caught in catch block — always pass the exception object |
| `_logger.Debug(message)` | Detailed tracing (parameter values, loop counts) — optional |

---

## Inline Progress Logging (Optional but Common)

```csharp
_logger.Information($"Starting GetSomeData()");

var retVal = new DataTable();

try
{
    _logger.Information($"Querying schema: {_customSchema}, table: {tableName}");

    using (var conn = GetDbConnection())
    {
        // ...
        _logger.Information($"Query returned {retVal.Rows.Count} rows");
        ConnectionCleanup(conn);
    }
}
catch (Exception ex)
{
    _logger.Error(ex, "GetSomeData Exception");
}

_logger.Information($"Finished GetSomeData() - retVal: {retVal.Rows.Count} rows");
return retVal;
```

---

## What NOT to Do

```csharp
// WRONG — wrong logger type
private readonly ILogger _logger;
private readonly Serilog.ILogger _logger;

// WRONG — no start/finish logging
public DataTable GetData()
{
    using (var conn = GetDbConnection()) { ... }
}

// WRONG — silent catch
catch (Exception ex)
{
    // nothing here
}

// WRONG — no try/catch at all
public string GetValue()
{
    return conn.ExecuteScalar("...", CommandType.Text).ToString();
}
```
