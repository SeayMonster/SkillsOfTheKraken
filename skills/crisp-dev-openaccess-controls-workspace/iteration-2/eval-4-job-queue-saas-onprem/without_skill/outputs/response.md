# Handling SaaS vs On-Prem in an OA Control Submit Handler

The codebase already has a clear, consistent pattern for this. Here is how every piece fits together, drawn directly from the existing controls (`POGSplitUI`, `PogCopyVersion`, `FpCopyVersion`).

---

## The Core Concept

**On-prem** installations have a background Windows service that polls a job queue table (`cx_job`) and processes submitted jobs asynchronously. The web tier only needs to insert the job record and return to the user — the service picks it up later.

**SaaS** (BlueYonder-hosted) environments do not ship that background service. So when `DeploymentMode = SaaS`, the web tier must insert the job record *and immediately process it* in the same request before returning.

---

## Step 1: The Configuration Key

The mode is read from `~/Custom/Config/CrispCustomizations.config` (deployed alongside your control's DLL). Add `DeploymentMode` alongside your existing `CustomSchema` key:

```xml
<!-- OA_LifecycleManagement/Config/CrispCustomizations.config -->
<?xml version="1.0" encoding="utf-8" ?>
<configuration>
  <appSettings>
    <add key="CustomSchema"   value="ckbcustom" />
    <!-- "SaaS"  → process on submit (no background service available)  -->
    <!-- "OnPrem"→ insert job only; background service processes async   -->
    <add key="DeploymentMode" value="SaaS" />
    <add key="IsDebugging"    value="false" />
  </appSettings>
</configuration>
```

`ConfigurationHelper.GetConfigSetting` reads this file from the running web application's `~/Custom/Config/` virtual path.

---

## Step 2: IsSaaS() in CommandFactory

Add a simple `IsSaaS()` method to your `CommandFactory`. It reads the config key and returns `true` when the value is `"SaaS"` (case-insensitive):

```csharp
// In CommandFactory.cs
internal bool IsSaaS()
{
    var mode = ConfigurationHelper.GetConfigSetting("DeploymentMode") ?? string.Empty;
    _logger.Information($"IsSaaS: DeploymentMode='{mode}'");
    return string.Equals(mode, "SaaS", StringComparison.OrdinalIgnoreCase);
}
```

---

## Step 3: InsertJob() Returns the New Job DBKey

Your `cx_job_ins` stored procedure needs to return the newly created job's DBKey. The web tier captures it so that `ProcessJob()` can reference the same record:

```csharp
// In CommandFactory.cs
internal int InsertJob(object model, string username, string jobType)
{
    _logger.Information($"Starting InsertJob() jobType={jobType}");
    try
    {
        using (var conn = GetDbConnection())
        {
            var p = new DynamicParameters();
            p.Add("username", username,                          dbType: DbType.String, size: 200);
            p.Add("jobType",  jobType,                           dbType: DbType.String, size: 50);
            p.Add("status",   "Submitted",                       dbType: DbType.String, size: 50);
            p.Add("json",     JsonConvert.SerializeObject(model), dbType: DbType.String);

            var jobDbKey = conn.ExecuteScalar<int>(
                $"{_customSchema}.cx_job_ins", p,
                commandType: CommandType.StoredProcedure);

            _logger.Information($"Finished InsertJob() jobDbKey={jobDbKey}");
            return jobDbKey;
        }
    }
    catch (Exception ex) { _logger.Error(ex, "InsertJob Exception"); }
    return 0;
}
```

---

## Step 4: ProcessJob() — SaaS Inline Processing

```csharp
// In CommandFactory.cs
internal void ProcessJob(int jobDbKey)
{
    _logger.Information($"Starting ProcessJob() jobDbKey={jobDbKey}");
    try
    {
        using (var conn = GetDbConnection())
        {
            var p = new DynamicParameters();
            p.Add("job_dbkey", jobDbKey, dbType: DbType.Int32);
            conn.Execute(
                $"{_customSchema}.cx_pog_copy_process",
                p,
                commandType: CommandType.StoredProcedure);
        }
    }
    catch (Exception ex) { _logger.Error(ex, "ProcessJob Exception"); }
    _logger.Information("Finished ProcessJob()");
}
```

---

## Step 5: The Submit Handler

```csharp
private void Submit()
{
    _logger.Information("Starting Submit()");
    try
    {
        // 1. Build the model
        _uiModel = new PogCopyModel
        {
            Mode        = rdoMode.SelectedValue,
            ProjectCode = txtProjectCode.Text.Trim(),
            ObjectKeys  = ParseKeys(rawKeys)
        };

        if (_uiModel.ObjectKeys.Rows.Count == 0)
        {
            OnDisplayMessage(new MessageEventArgs
            {
                Message         = "No planograms selected.",
                EventType       = MessageEventTypes.Warning,
                MessageLocation = MessageLocations.BottomLeft
            });
            return;
        }

        // 2. Determine deployment mode
        var isSaaS  = _commandFactory.IsSaaS();
        var jobType = "Planogram Copy";

        // 3. Always insert the job record — works for both modes
        var jobDbKey = _commandFactory.InsertJob(_uiModel, Helper.CurrentUser, jobType);

        _logger.Information($"Submit: isSaaS={isSaaS}, jobDbKey={jobDbKey}");

        // 4. SaaS only: process the job immediately in-process
        if (isSaaS)
        {
            _logger.Information("Submit: calling ProcessJob");
            _commandFactory.ProcessJob(jobDbKey);
        }
        // On-prem: return immediately; background service will pick up the job

        // 5. Publish a grid refresh signal
        SubscriptionManager.Publish(this, "_updated", 1);

        // 6. Show the appropriate success message
        var count = _uiModel.ObjectKeys.Rows.Count;
        OnDisplayMessage(new MessageEventArgs
        {
            Message         = isSaaS
                ? $"{count} planogram(s) copied successfully."
                : $"Job submitted: {count} planogram(s) queued for {jobType}.",
            EventType       = MessageEventTypes.Success,
            MessageLocation = MessageLocations.BottomLeft
        });
    }
    catch (Exception ex) { _logger.Error(ex, "Submit Exception"); }
    _logger.Information("Finished Submit()");
}
```

---

## Key Design Rules

| Rule | Reason |
|---|---|
| Call `IsSaaS()` once per Submit, store in local variable | Avoids re-reading config mid-operation; value is logged before branching |
| Always insert the job record regardless of mode | On-prem needs it in the queue; SaaS needs the DBKey to pass to `ProcessJob` |
| `InsertJob` returns `int` (the new job DBKey), not `void` | Enables the SaaS path to call `ProcessJob(jobDbKey)` targeting the exact row |
| The success message differs by mode | Tells the user whether the work is done (SaaS) or pending (OnPrem) |
| `ProcessJob` only knows a `job_dbkey` | Keeps the web tier thin; all business logic stays in SQL |
