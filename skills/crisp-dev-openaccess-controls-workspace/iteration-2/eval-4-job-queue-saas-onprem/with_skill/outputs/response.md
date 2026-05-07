# Handling SaaS vs. On-Prem in a Submit Button Handler for a Long-Running OA Operation

## The Core Problem

In OA control development, a planogram copy operation is long-running and cannot safely complete inline in every environment. The OA platform supports two deployment models — BlueYonder-hosted (SaaS) and on-premises — and they handle background work very differently. Your `Submit()` handler must branch based on which model is active, reading this from config rather than hardcoding it.

---

## Deployment Mode Decision

Before writing any submit logic, understand the two modes:

| Mode | What Submit does |
|---|---|
| **SaaS** (BlueYonder-hosted) | Insert job row then immediately call the process proc in the same web request. BY does not allow background services to run in their environment. |
| **OnPrem** | Insert job row only. A Windows service / Automator process polls `cx_job` and calls the process proc asynchronously. |

Both paths always insert the job row first. This gives you a tracking/audit record regardless of how the job is processed. The only difference is whether the process proc is called right away or deferred.

Set the mode in `~/Custom/Config/CXCustomizations.config`:

```xml
<!-- SaaS (BlueYonder-hosted) -->
<add key="DeploymentMode" value="SaaS" />

<!-- On-Prem -->
<add key="DeploymentMode" value="OnPrem" />
```

Never hardcode the mode in C#. Always read it from config at runtime.

---

## Step 1: The `cx_job` Table

```sql
CREATE TABLE [ckbcustom].[cx_job] (
    [dbkey]      [int]            IDENTITY(1,1) NOT NULL,
    [dbtime]     [datetime]       NOT NULL DEFAULT GETDATE(),
    [Username]   [varchar](100)   NOT NULL,
    [JobType]    [varchar](50)    NOT NULL,
    [Status]     [varchar](25)    NOT NULL,
    [Parameters] [nvarchar](max)  NOT NULL,
    PRIMARY KEY CLUSTERED ([dbkey] ASC)
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY];
GO
GRANT SELECT, UPDATE, INSERT, DELETE ON [ckbcustom].[cx_job] TO public;
```

---

## Step 2: The Insert Stored Procedure

`cx_job_ins` inserts the job and returns the new row's DBKey via `SCOPE_IDENTITY()`.

```sql
CREATE OR ALTER PROCEDURE ckbcustom.cx_job_ins (
    @username VARCHAR(200),
    @jobType  VARCHAR(50),
    @status   VARCHAR(50),
    @json     NVARCHAR(MAX)
)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ckbcustom.cx_job (Username, JobType, Status, Parameters)
    VALUES (@username, @jobType, @status, @json);

    SELECT SCOPE_IDENTITY() AS JobDBKey;
END;
GO
GRANT EXECUTE ON ckbcustom.cx_job_ins TO public;
```

---

## Step 3: The Process Stored Procedure

```sql
CREATE OR ALTER PROCEDURE ckbcustom.cx_pog_copy_process
    @job_dbkey INT = NULL   -- NULL = OnPrem service path; value = SaaS single job
AS
BEGIN
    SET NOCOUNT ON;

    IF @job_dbkey IS NULL
    BEGIN
        -- OnPrem: loop all Submitted jobs of this type
        DECLARE @cur_key INT;
        DECLARE job_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DBKey FROM ckbcustom.cx_job
            WHERE JobType = 'POG Copy' AND Status = 'Submitted'
            ORDER BY DBKey;

        OPEN job_cursor;
        FETCH NEXT FROM job_cursor INTO @cur_key;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC ckbcustom.cx_pog_copy_process @job_dbkey = @cur_key;
            FETCH NEXT FROM job_cursor INTO @cur_key;
        END;
        CLOSE job_cursor;
        DEALLOCATE job_cursor;
        RETURN;
    END;

    -- Single-job path: fetch JSON from the job table
    DECLARE @json NVARCHAR(MAX);
    SELECT @json = Parameters FROM ckbcustom.cx_job WHERE DBKey = @job_dbkey;

    IF @json IS NULL
        THROW 50000, 'cx_pog_copy_process: Job not found or has no parameters.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        -- Parse @json and perform the planogram copy here
        COMMIT TRANSACTION;

        UPDATE ckbcustom.cx_job SET Status = 'Completed' WHERE DBKey = @job_dbkey;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
GRANT EXECUTE ON ckbcustom.cx_pog_copy_process TO public;
```

---

## Step 4: CommandFactory Methods

```csharp
internal bool IsSaaS()
{
    var mode = ConfigurationHelper.GetConfigSetting("DeploymentMode") ?? string.Empty;
    _logger.Information($"IsSaaS: DeploymentMode='{mode}'");
    return string.Equals(mode, "SaaS", StringComparison.OrdinalIgnoreCase);
}

internal int InsertJob(object model, string username, string jobType)
{
    _logger.Information($"Starting InsertJob() jobType={jobType}");
    try
    {
        using (var conn = GetDbConnection())
        {
            var p = new DynamicParameters();
            p.Add("username", username,                           dbType: DbType.String, size: 200);
            p.Add("jobType",  jobType,                            dbType: DbType.String, size: 50);
            p.Add("status",   "Submitted",                        dbType: DbType.String, size: 50);
            p.Add("json",     JsonConvert.SerializeObject(model),  dbType: DbType.String);
            var jobDbKey = conn.ExecuteScalar<int>(
                $"{_customSchema}.cx_job_ins", p, commandType: CommandType.StoredProcedure);
            ConnectionCleanup(conn);
            _logger.Information($"Finished InsertJob() jobDbKey={jobDbKey}");
            return jobDbKey;
        }
    }
    catch (Exception ex) { _logger.Error(ex, "InsertJob Exception"); }
    return 0;
}

internal void ProcessJob(int jobDbKey)
{
    _logger.Information($"Starting ProcessJob() jobDbKey={jobDbKey}");
    try
    {
        using (var conn = GetDbConnection())
        {
            var p = new DynamicParameters();
            p.Add("job_dbkey", jobDbKey, dbType: DbType.Int32);
            conn.Execute($"{_customSchema}.cx_pog_copy_process", p,
                commandType: CommandType.StoredProcedure);
            ConnectionCleanup(conn);
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

    // 1. Sync client-side list state into the model before doing anything else
    SyncModelFromHiddenField();

    // 2. Publish synced state — ensures re-submission after validation failure works
    PublishModel();

    // 3. Validate
    if (_uiModel.SourcePogKey <= 0)
    {
        OnDisplayMessage(new MessageEventArgs()
        {
            Message         = "Please select a source planogram.",
            EventType       = MessageEventTypes.Error,
            MessageLocation = MessageLocations.BottomLeft
        });
        return;
    }

    // 4. Read deployment mode once
    var isSaaS = _commandFactory.IsSaaS();

    // 5. Always insert the job — both modes
    var jobDbKey = _commandFactory.InsertJob(_uiModel, Helper.CurrentUser, "POG Copy");

    if (isSaaS)
    {
        // 6a. SaaS: no background service — process immediately in this request
        _commandFactory.ProcessJob(jobDbKey);
    }
    // 6b. OnPrem: return immediately; Automator/service polls cx_job

    // 7. Reset state
    _uiModel = new PogCopyModel();
    SubscriptionManager.Publish(this, CommonConstants.SESSION_SelectedPogKey, string.Empty);
    PublishModel();

    // 8. Mode-appropriate success message
    OnDisplayMessage(new MessageEventArgs()
    {
        Message         = isSaaS
            ? "Planogram copy completed successfully."
            : "Copy job submitted. The operation will be processed shortly.",
        EventType       = MessageEventTypes.Success,
        MessageLocation = MessageLocations.BottomLeft
    });

    _logger.Information("Finished Submit()");
}
```

---

## Key Rules

1. **Always insert the job row first** — both modes do this for tracking/auditing.
2. **`InsertJob` returns the new DBKey** — capture it and pass it to `ProcessJob` on the SaaS path.
3. **Read `DeploymentMode` from config, never hardcode it** — use `ConfigurationHelper.GetConfigSetting("DeploymentMode")`. The `IsSaaS()` helper encapsulates this.
4. **Read the mode once per submit, store in a local variable** — call it once and reuse `isSaaS` for both the branch and the success message.
5. **The process proc's `@job_dbkey = NULL` path is for the OnPrem service** — your C# code never calls the proc with NULL; the background service does.
6. **`SyncModelFromHiddenField()` + `PublishModel()` must come before validation** — client-side list state isn't carried by postback; the hidden field holds it.
7. **Tailor the success message to the mode** — SaaS users: "done"; OnPrem users: "queued".
