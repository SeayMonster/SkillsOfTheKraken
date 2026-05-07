# Code Review: GetStoreCodes

## Issues Found

**1. async/await is not used in this codebase (Critical)**

The method signature `public async Task<List<string>> GetStoreCodes(...)` violates the project's synchronous-only rule. This codebase is fully synchronous — `async`, `await`, and `Task<T>` are never used. The `QueryAsync` call follows from the same mistake.

**2. Direct `new SqlConnection(...)` instead of `GetDbConnection()` (Critical)**

Connection management must always go through `GetDbConnection()`. Direct construction bypasses the `IKBDbSupport`-managed connection (which controls timeout and connection string sourcing) and is explicitly listed as a prohibited pattern.

**3. Connection is never closed or disposed (Critical)**

`conn.Open()` is called but there is no `using` block and no `ConnectionCleanup(conn)` call. The connection leaks on every invocation, including on any exception path.

**4. Missing Start/Finish logging and try/catch (Critical)**

Every method must begin with `_logger.Information($"Starting MethodName()")`, wrap all logic in `try { }`, catch with `_logger.Error(ex, "MethodName Exception")`, and end with `_logger.Information($"Finished MethodName() - retVal: ...")` before the return. None of that structure is present.

**5. Bare inline SQL instead of a stored procedure (Convention)**

The convention is to call stored procedures via `conn.ExecuteReader(...)` with `CommandType.StoredProcedure`. Inline SQL is not the standard pattern for list queries.

**6. `schemaName` passed as a parameter instead of using `_customSchema` (Convention)**

Schema is loaded from app.config and injected into `CommandFactory` via the constructor, stored as `_customSchema`. Accepting it as a loose method parameter bypasses this and risks inconsistency.

**7. Redundant variable initialization**

`var storeCodes = new List<string>()` is declared and then immediately overwritten. The convention is to declare `retVal` once, assign inside `try`, and return at the bottom.

---

## Corrected Code

```csharp
internal List<string> GetStoreCodes()
{
    _logger.Information($"Starting GetStoreCodes()");

    var retVal = new List<string>();

    try
    {
        using (var conn = GetDbConnection())
        {
            var reader = conn.ExecuteReader(
                $"{_customSchema}.cx_store_codes_get",
                commandType: CommandType.StoredProcedure);

            var dt = new DataTable();
            dt.Load(reader);

            foreach (DataRow row in dt.Rows)
            {
                retVal.Add(row["StoreCode"].ToString());
            }

            ConnectionCleanup(conn);
        }
    }
    catch (Exception ex)
    {
        _logger.Error(ex, "GetStoreCodes Exception");
    }

    _logger.Information($"Finished GetStoreCodes() - retVal: {retVal.Count} items");
    return retVal;
}
```
