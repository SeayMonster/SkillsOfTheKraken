# Code Review

### Issue 1 — SqlConnection is never disposed (Critical)
The `SqlConnection` is opened but never closed or disposed. If an exception is thrown before the method returns, the connection leaks. Over time this exhausts the connection pool and causes the application to stop accepting database requests.

**Fix:** Wrap the connection in a `using` (or `await using`) statement.

---

### Issue 2 — Synchronous `Open()` used inside an async method (Bug)
`conn.Open()` blocks the calling thread. Since the method is `async`, it should use `await conn.OpenAsync()` to yield the thread while the connection is being established.

---

### Issue 3 — SQL injection via schema name interpolation (Security)
`schemaName` is interpolated directly into the SQL string. Schema/table names cannot be parameterized with `@param` syntax in SQL, so if an untrusted caller passes a malicious value, they can execute arbitrary SQL. This must be validated or whitelisted before being used in the query.

**Fix:** Validate that `schemaName` only contains safe characters (alphanumeric + underscore) before using it.

---

### Issue 4 — Redundant variable initialization (Minor)
`storeCodes` is initialized to `new List<string>()` and then immediately overwritten. The first allocation is wasted.

---

### Issue 5 — Unnecessary intermediate variable (Minor)
`result` and `storeCodes` are two separate variables that do the same thing. The result can be returned directly.

---

### Corrected Version

```csharp
public async Task<List<string>> GetStoreCodes(string schemaName)
{
    if (!IsValidSchemaName(schemaName))
        throw new ArgumentException("Invalid schema name.", nameof(schemaName));

    await using var conn = new SqlConnection(_connectionString);
    await conn.OpenAsync();

    var result = await conn.QueryAsync<string>(
        $"SELECT StoreCode FROM {schemaName}.Stores WHERE IsActive = 1");

    return result.ToList();
}

private static bool IsValidSchemaName(string name) =>
    !string.IsNullOrWhiteSpace(name) &&
    System.Text.RegularExpressions.Regex.IsMatch(name, @"^[a-zA-Z_][a-zA-Z0-9_]*$");
```
