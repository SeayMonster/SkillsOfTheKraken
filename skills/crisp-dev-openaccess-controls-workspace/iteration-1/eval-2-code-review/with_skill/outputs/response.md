# Code Review: BadControl

This control has multiple violations of the OA control development standards.

## 1. Raw ADO.NET Instead of CommandFactory + Dapper

All database work must go through a `CommandFactory` class using Dapper and `DynamicParameters`. Raw `SqlConnection`, `SqlCommand`, and `ExecuteNonQuery` are never permitted.

**Correct approach:**
```csharp
case "Save":
    _commandFactory.SaveSettings(txtValue.Text);
    break;
```
Where `CommandFactory.SaveSettings` uses `DynamicParameters` and calls a stored procedure via `conn.Execute(..., commandType: CommandType.StoredProcedure)`.

## 2. Hardcoded Connection String

Connection strings must never be hardcoded. `CommandFactory.GetDbConnection()` calls `_support.CreateDbConnection().ConnectionString`, which reads the connection from the OA framework's own configuration (`IKBDbSupport`).

## 3. Hardcoded Schema Name

`ckbcustom` must never be hardcoded directly in C# code. The custom schema is read at runtime from `CXCustomizations.config` via `ConfigurationHelper`:

```csharp
_customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");
```

It is then passed to `CommandFactory`, which uses it as `$"{_customSchema}.cx_settings_ins"`.

## 4. Inline SQL Instead of a Stored Procedure

Inline SQL is not permitted. All data access goes through stored procedures named `{schema}.cx_[noun]_[verb]`. The proc file must end with:

```sql
GO
GRANT EXECUTE ON ckbcustom.cx_settings_ins TO public;
```

## 5. No Error Handling

`DoCommand` must wrap its entire body in a `try/catch` that logs exceptions via `_logger.Error`.

```csharp
public void DoCommand(CommandEventArgs e)
{
    try
    {
        switch (e.CommandName)
        {
            case "Save":
                _commandFactory.SaveSettings(txtValue.Text);
                SubscriptionManager.Publish(this, "_updated", 1);
                OnDisplayMessage(new MessageEventArgs()
                {
                    Message = "Saved successfully.",
                    EventType = MessageEventTypes.Success,
                    MessageLocation = MessageLocations.BottomLeft
                });
                break;
        }
    }
    catch (Exception ex) { _logger.Error(ex, "DoCommand Exception"); }
}
```

## 6. No Logging

Every control must declare a static `Logger` via `ConfigurationHelper.CreateLogger`, and every significant method must emit Start/Finish `_logger.Information()` calls.

```csharp
private static readonly Logger _logger = ConfigurationHelper.CreateLogger("BadControl");
```

## 7. `Response.Write` Instead of `OnDisplayMessage`

User feedback must always go through `OnDisplayMessage()`. `Response.Write` breaks OA page rendering.

```csharp
OnDisplayMessage(new MessageEventArgs()
{
    Message = "Saved successfully.",
    EventType = MessageEventTypes.Success,
    MessageLocation = MessageLocations.BottomLeft
});
```

## 8. Connection Not Disposed on Exception

Connections must always be managed inside a `using` block with `ConnectionCleanup(conn)`.

## 9. `GetCommands` Not Implemented

`ICommandManager` requires both `GetCommands()` and `DoCommand()`. Without `GetCommands()` the toolbar renders nothing.

---

## Summary

| # | Issue | Rule |
|---|---|---|
| 1 | Raw ADO.NET | Use CommandFactory + Dapper only |
| 2 | Hardcoded connection string | Must come from IKBDbSupport via GetDbConnection() |
| 3 | Hardcoded schema `"ckbcustom"` | Read from config via ConfigurationHelper |
| 4 | Inline SQL | All SQL goes through stored procs |
| 5 | No try/catch | Must wrap all work in try/catch with _logger.Error |
| 6 | No logging | Static Logger; Start/Finish on every method |
| 7 | Response.Write | Use OnDisplayMessage() exclusively |
| 8 | Connection not disposed | Use using + ConnectionCleanup(conn) |
| 9 | GetCommands() missing | ICommandManager requires both methods |
