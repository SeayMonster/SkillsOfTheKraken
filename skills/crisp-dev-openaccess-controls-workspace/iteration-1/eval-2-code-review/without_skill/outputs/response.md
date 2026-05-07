# Code Review: BadControl

## 1. Hardcoded Connection String

```csharp
var conn = new SqlConnection("Server=myserver;Database=ckb;");
```

The connection string is embedded directly in source code. Connection strings should be stored in a configuration source (e.g., `web.config` or a centralized configuration service) and retrieved at runtime. Hardcoding server names creates a maintenance burden and is a security risk if the code is committed to source control or shared.

## 2. No Resource Disposal (Missing `using` Blocks)

`SqlConnection` and `SqlCommand` both implement `IDisposable`. Neither is wrapped in a `using` block. If an exception occurs between `conn.Open()` and `conn.Close()`, the connection will never be closed, leaking it back to the pool indefinitely. The correct pattern:

```csharp
using (var conn = new SqlConnection(connectionString))
using (var cmd = new SqlCommand("...", conn))
{
    // ...
}
```

## 3. No Exception Handling

There is no `try/catch` around the database call. Any SQL exception (network failure, constraint violation, timeout) will propagate unhandled up the call stack, likely resulting in a raw error page shown to the user. Database operations should be wrapped in error handling with appropriate user feedback and logging.

## 4. `Response.Write` for User Feedback

```csharp
Response.Write("Saved!");
```

`Response.Write` injects raw text directly into the page output stream at an unpredictable location in the rendered HTML. In an OpenAccess control, user feedback should be delivered through the control's established UI mechanism — typically a label, notification panel, or status message property — not by writing directly to the response.

## 5. No Input Validation

`txtValue.Text` is accepted with no length check, format check, null/empty check, or business-rule validation before being persisted. All user input should be validated before it reaches the database.

## 6. Missing Column List in INSERT

```sql
INSERT INTO ckbcustom.cx_settings VALUES (@val)
```

The `INSERT` omits the target column list. Always specify columns explicitly.

## 7. Class Naming

`BadControl` is not a meaningful, descriptive name for a production control.

---

## Summary

| Issue | Severity |
|---|---|
| Hardcoded connection string | High |
| No resource disposal (missing `using`) | High |
| No exception handling | High |
| `Response.Write` for user feedback | Medium |
| No input validation | Medium |
| Missing column list in `INSERT` | Medium |
| Class naming | Low |
