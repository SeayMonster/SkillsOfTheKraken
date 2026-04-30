# Dapper Patterns Reference

Based on SampleSpaceBRV\HelperClasses\CommandFactory.cs and Blackhawk ProductExport.

---

## NuGet Package

```
Dapper 2.1.35
```

---

## CommandFactory.cs Boilerplate (Complete File)

```csharp
#region
using MyProjectAssembly.Models;

using Dapper;

using JDA.Intactix.IKB.DataAccess;

using Serilog.Core;

using System;
using System.Data;
using System.Data.SqlClient;
#endregion

namespace MyProjectAssembly.HelperClasses
{
    public class CommandFactory
    {
        private readonly IKBDbSupport _support;
        private readonly Logger _logger;
        private SqlConnection _connectionString;
        private readonly string _customSchema;

        public CommandFactory(IKBDbSupport support, string customSchema, Logger logger)
        {
            _support      = support;
            _customSchema = customSchema;
            _logger       = logger;
        }

        public CommandFactory(IKBDbSupport support, string customSchema)
        {
            _support      = support;
            _customSchema = customSchema;
        }

        public IDbConnection GetDbConnection()
        {
            _connectionString = new SqlConnection(_support.CreateDbConnection().ConnectionString);
            return _connectionString;
        }

        private static void ConnectionCleanup(IDbConnection conn)
        {
            conn.Close();
            conn.Dispose();
        }

        // Add methods here
    }
}
```

---

## Connection Management Rules

- **Always** use `GetDbConnection()` to open a connection — never `new SqlConnection(...)` directly
  inside a method.
- **Always** call `ConnectionCleanup(conn)` before the `using` block ends.
- **Always** wrap the connection in a `using` block.
- Connection timeout is controlled by `IKBDbSupport` (600 seconds default).

```csharp
using (var conn = GetDbConnection())
{
    // do work
    ConnectionCleanup(conn);
}
```

---

## Pattern 1: Stored Procedure → DataTable

```csharp
internal DataTable GetProductData(string ckbTable, string aleNumber)
{
    _logger.Information($"Starting GetProductData()");

    var retVal = new DataTable();

    try
    {
        using (var conn = GetDbConnection())
        {
            var parameters = new DynamicParameters();
            parameters.Add("ckb_table", ckbTable);
            parameters.Add("ale_number", aleNumber);

            var reader = conn.ExecuteReader(
                $"{_customSchema}.cx_product_data_get",
                parameters,
                commandType: CommandType.StoredProcedure);

            retVal.Load(reader);
            ConnectionCleanup(conn);
        }
    }
    catch (Exception ex)
    {
        _logger.Error(ex, "GetProductData Exception");
    }

    _logger.Information($"Finished GetProductData() - retVal: {retVal.Rows.Count} rows");
    return retVal;
}
```

---

## Pattern 2: Stored Procedure → bool (with out DataTable)

```csharp
internal bool ValidateData(DataTable inputData, string ckbTable, out DataTable badData)
{
    _logger.Information($"Starting ValidateData()");

    var retVal = false;
    var tmpBadData = new DataTable();

    try
    {
        using (var conn = GetDbConnection())
        {
            var parameters = new DynamicParameters();
            parameters.Add("ckb_table", ckbTable);
            parameters.Add("json", Newtonsoft.Json.JsonConvert.SerializeObject(inputData));

            var reader = conn.ExecuteReader(
                $"{_customSchema}.cx_validate_data",
                parameters,
                commandType: CommandType.StoredProcedure);

            tmpBadData.Load(reader);

            if (tmpBadData.Rows.Count > 0)
            {
                retVal = true;
            }

            ConnectionCleanup(conn);
        }
    }
    catch (Exception ex)
    {
        _logger.Error(ex, "ValidateData Exception");
    }

    badData = tmpBadData;

    _logger.Information($"Finished ValidateData() - retVal: {retVal}");
    return retVal;
}
```

---

## Pattern 3: ExecuteScalar → string

```csharp
internal string GetPageKey(string pageName)
{
    _logger.Information($"Starting GetPageKey()");

    var retVal = string.Empty;

    try
    {
        using (var conn = GetDbConnection())
        {
            retVal = conn.ExecuteScalar(
                $"SELECT dbkey FROM ix_web_page WHERE name = '{pageName}'",
                commandType: CommandType.Text).ToString();

            ConnectionCleanup(conn);
        }
    }
    catch (Exception ex)
    {
        _logger.Error(ex, "GetPageKey Exception");
    }

    _logger.Information($"Finished GetPageKey() - retVal: {retVal}");
    return retVal;
}
```

---

## Pattern 4: Stored Procedure → no return (Execute)

```csharp
internal void UpdateProductStatus(int productKey, string status)
{
    _logger.Information($"Starting UpdateProductStatus()");

    try
    {
        using (var conn = GetDbConnection())
        {
            var parameters = new DynamicParameters();
            parameters.Add("product_key", productKey, DbType.Int32);
            parameters.Add("status", status, DbType.String);

            conn.Execute(
                $"{_customSchema}.cx_product_status_update",
                parameters,
                commandType: CommandType.StoredProcedure);

            ConnectionCleanup(conn);
        }
    }
    catch (Exception ex)
    {
        _logger.Error(ex, "UpdateProductStatus Exception");
    }

    _logger.Information($"Finished UpdateProductStatus()");
}
```

---

## DynamicParameters — Adding Values

```csharp
var parameters = new DynamicParameters();

// String (no DbType needed — Dapper infers)
parameters.Add("param_name", someStringValue);

// Explicit DbType (use when type matters for stored proc)
parameters.Add("product_key", productKey, DbType.Int32);
parameters.Add("amount", amount, DbType.Decimal);
parameters.Add("flag", isActive, DbType.Boolean);
parameters.Add("ale", aleNumber?.Trim(), DbType.String);
```

---

## Naming Conventions for CommandFactory Methods

| Pattern | Method Name | Returns |
|---------|-------------|---------|
| Fetch list | `Get{Thing}Data()` or `Get{Things}()` | `DataTable` |
| Fetch single scalar | `Get{Thing}Key()` or `Get{Thing}Name()` | `string` |
| Validate / check | `Is{Condition}()` | `bool` |
| Insert/update | `Update{Thing}()` or `Save{Thing}()` | `void` |
| Delete | `Delete{Thing}()` | `void` or `bool` |

---

## Stored Procedure Naming Convention

Stored procedures follow the pattern: `{schema}.cx_{object}_{action}`

The schema name is read from app.config (`CustomSchema` key) and passed into `CommandFactory`
via the constructor. Reference it via `_customSchema` in every stored proc call:

```csharp
conn.ExecuteReader($"{_customSchema}.cx_product_data_get", parameters, ...);
```

Examples:
- `ckbcustom.cx_product_data_get`
- `ckbcustom.cx_importer_bad_col_chk`
- `ckbcustom.cx_reports_generate`
- `ckbcustom.cx_product_status_update`

Always reference via `$"{_customSchema}.cx_..."` — never hardcode the schema name inline.

---

## CommonConstants.cs Pattern

Static string constants for all table names, stored proc names, and shared strings:

```csharp
namespace MyProjectAssembly.HelperClasses
{
    internal static class CommonConstants
    {
        // CKB Table Names
        internal const string CKB_Table_Products = "ix_spc_product";
        internal const string CKB_Table_Planograms = "ix_spc_planogram";
        internal const string CKB_Table_Positions = "ix_spc_position";

        // Stored Procedure Names (without schema — schema added at call site)
        internal const string SP_ProductDataGet = "cx_product_data_get";
        internal const string SP_ProductStatusUpdate = "cx_product_status_update";
    }
}
```

Usage:
```csharp
conn.ExecuteReader($"{_customSchema}.{CommonConstants.SP_ProductDataGet}", parameters, ...);
```

---

## What NOT to Do

```csharp
// WRONG — direct SqlConnection without GetDbConnection()
var conn = new SqlConnection(someConnectionString);

// WRONG — no ConnectionCleanup
using (var conn = GetDbConnection())
{
    retVal.Load(conn.ExecuteReader(...));
    // ConnectionCleanup missing!
}

// WRONG — hardcoded schema string inline
conn.ExecuteReader("ckbcustom.cx_product_data_get", ...);  // use _customSchema instead

// WRONG — async/await (not used in this codebase)
var result = await conn.QueryAsync(...);

// WRONG — LINQ/Entity Framework (use Dapper only)
var result = _context.Products.Where(p => p.Key == key).ToList();
```
