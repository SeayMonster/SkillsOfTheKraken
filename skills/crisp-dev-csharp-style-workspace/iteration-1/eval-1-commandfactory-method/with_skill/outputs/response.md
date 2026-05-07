# CommandFactory Method: GetPlanogramsByStore

Below is the `GetPlanogramsByStore` method ready to paste into your `CommandFactory` class. It follows all Crisp/Blue Yonder C# coding conventions: Start/Finish Serilog logging, try/catch, Dapper `DynamicParameters`, `ExecuteReader` → `DataTable`, and `ConnectionCleanup`.

```csharp
internal DataTable GetPlanogramsByStore(string storeNumber)
{
    _logger.Information($"Starting GetPlanogramsByStore()");

    var retVal = new DataTable();

    try
    {
        using (var conn = GetDbConnection())
        {
            var parameters = new DynamicParameters();
            parameters.Add("store_number", storeNumber);

            var reader = conn.ExecuteReader(
                $"{_customSchema}.cx_planograms_by_store_get",
                parameters,
                commandType: CommandType.StoredProcedure);

            retVal.Load(reader);
            ConnectionCleanup(conn);
        }
    }
    catch (Exception ex)
    {
        _logger.Error(ex, "GetPlanogramsByStore Exception");
    }

    _logger.Information($"Finished GetPlanogramsByStore() - retVal: {retVal.Rows.Count} rows");
    return retVal;
}
```

**Notes:**
- `internal` visibility matches all `CommandFactory` DB methods.
- `store_number` is passed to `DynamicParameters` without an explicit `DbType` — Dapper infers `string`.
- Stored procedure is referenced as `$"{_customSchema}.cx_planograms_by_store_get"` — schema is never hardcoded.
- Exception is logged and swallowed at the data layer, returning an empty `DataTable` to the caller.
- `ConnectionCleanup(conn)` is called before the `using` block exits.
- No async/await — codebase is fully synchronous.
