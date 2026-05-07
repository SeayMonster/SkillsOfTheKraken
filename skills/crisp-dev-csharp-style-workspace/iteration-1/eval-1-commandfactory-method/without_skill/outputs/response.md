# GetPlanogramsByStore — CommandFactory Method

Here is the `GetPlanogramsByStore` method to add to the `CommandFactory` class:

```csharp
/// <summary>
/// Returns all planograms assigned to the specified store.
/// SP: {schema}.cx_planograms_by_store_get
/// </summary>
internal DataTable GetPlanogramsByStore(string storeNumber)
{
    _logger.Information($"Starting GetPlanogramsByStore() storeNumber={storeNumber}");
    var retVal = new DataTable();
    try
    {
        using (var conn = GetDbConnection())
        {
            var p = new DynamicParameters();
            p.Add("StoreNumber", storeNumber, dbType: DbType.String, size: 50);
            retVal.Load(conn.ExecuteReader(
                $"{_customSchema}.cx_planograms_by_store_get",
                p,
                commandType: CommandType.StoredProcedure));
        }
    }
    catch (Exception ex) { _logger.Error(ex, $"GetPlanogramsByStore Exception storeNumber={storeNumber}"); }
    _logger.Information("Finished GetPlanogramsByStore()");
    return retVal;
}
```
