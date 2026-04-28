# OA Control Code Patterns Reference

## Schema and SQL Naming Conventions

The custom database schema is **`ckbcustom`**, read at runtime from
`~/Custom/Config/CXCustomizations.config`:

```xml
<add key="CustomSchema" value="ckbcustom" />
```

This value is passed to `CommandFactory` via:

```csharp
var customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");
_commandFactory  = new CommandFactory(KBDbSupport, customSchema, _logger);
```

### Naming rules (all SQL objects under `ckbcustom`)

| Object type | Pattern | Example |
|---|---|---|
| Stored procedure | `ckbcustom.cx_<noun>_<verb>` | `ckbcustom.cx_page_key_get` |
| Table | `ckbcustom.cx_<noun>` | `ckbcustom.cx_job` |
| View | `ckbcustom.cx_<noun>_vw` | `ckbcustom.cx_pog_status_vw` |
| Table-valued type | `ckbcustom.cx_<noun>_type` | `ckbcustom.cx_int_list_type` |

SQL files mirror the fully qualified object name:

| Object type | File name pattern | Example |
|---|---|---|
| Stored procedure | `ckbcustom.cx_<noun>_<verb>.sql` | `ckbcustom.cx_page_key_get.sql` |
| Table-valued type | `ckbcustom.cx_<noun>_type.sql` | `ckbcustom.cx_int_list_type.sql` |
| View | `ckbcustom.cx_<noun>_vw.sql` | `ckbcustom.cx_pog_status_vw.sql` |

SQL files use `CREATE OR ALTER` so they are safe to re-run on every deploy.
Always qualify every object with the `ckbcustom.` schema prefix — never use bare names.

Every stored procedure file must end with a `GRANT EXECUTE` to `public` after the `END;`:

```sql
CREATE OR ALTER PROCEDURE ckbcustom.cx_example_get
    @Param INT
AS
BEGIN
    SET NOCOUNT ON;
    -- body
END;
GO
GRANT EXECUTE ON ckbcustom.cx_example_get TO public;
```

---

## Table of Contents
1. [CommandFactory Pattern](#commandfactory-pattern)
2. [ConfigurationHelper Pattern](#configurationhelper-pattern)
3. [Planogram Selection Pattern — Multi-select](#planogram-selection-pattern--multi-select)
3b. [Planogram Selection Pattern — Single-select](#planogram-selection-pattern--single-select)
4. [Standalone Control (UserControlBase)](#standalone-control-usercontrolbase)
5. [Standalone Control — Model Lifecycle Pattern](#standalone-control--model-lifecycle-pattern)
6. [Derived Grid Control](#derived-grid-control)
7. [Job Queue Pattern](#job-queue-pattern)
8. [Opening a Custom ASCX Popup](#opening-a-custom-ascx-popup)
9. [Custom Single-Select Popup (IPopupCommandManager)](#custom-single-select-popup-ipopupcommandmanager)
10. [Client-side ListBox Transfer Pattern](#client-side-listbox-transfer-pattern)
11. [JavaScript File Wiring](#javascript-file-wiring)
12. [CSS Conventions and Wiring](#css-conventions-and-wiring)
12. [Fieldset Group Box Pattern](#fieldset-group-box-pattern)
13. [SessionHelper Pattern](#sessionhelper-pattern)
14. [Model Classes](#model-classes)
15. [Custom Page Registry](#custom-page-registry)

---

## Custom Page Registry

All custom OA pages live in `ix_web_page` with `DBKey >= 127`.
Base platform pages occupy `DBKey 1–126` and must never be modified.

Page registration is maintained in:
`OA_LifecycleManagement\SQL\Configuration\RegisterPages.sql`

Run against the target CKB database (not `ckbXXXXX` training databases):
```powershell
Invoke-Sqlcmd -ServerInstance "cx-lpt943\v2022" -Database "ckb" `
    -InputFile "OA_LifecycleManagement\SQL\Configuration\RegisterPages.sql"
```

### Current custom pages (server: cx-lpt943\v2022, database: ckb)

| DBKey | Name              | Parent DBKey | Parent Name      | Level | SortOrder | IsHidden |
|-------|-------------------|--------------|------------------|-------|-----------|----------|
| 127   | Academy           | 1            | Intactix         | 2     | 111       | 0        |
| 128   | Copy/Version      | 127          | Academy          | 3     | NULL      | 0        |
| 131   | POG Copy Version  | 128          | Copy/Version     | 4     | 1         | 1        |
| 132   | FP Copy Version   | 128          | Copy/Version     | 4     | 2         | 1        |

### Page name constants (`CommonConstants.cs`)

```csharp
public const string PAGE_PogCopyVersion = "POG Copy Version";
public const string PAGE_FpCopyVersion  = "FP Copy Version";
```

These must match the `Name` column in `ix_web_page` exactly — they are passed to
`_commandFactory.GetPageKey(pageName)` which calls `cx_page_key_get`.

### Adding a new custom page

1. Add a row to the `MERGE` source in `RegisterPages.sql` (Step 3) or add a new
   `IF NOT EXISTS / INSERT ... SELECT` step if it needs a dynamically resolved parent.
2. Add the corresponding constant to `CommonConstants.cs`.
3. Run `RegisterPages.sql` against every target CKB database.

---

## CommandFactory Pattern

```csharp
using System.Data;
using System.Data.SqlClient;
using Dapper;
using Serilog;

public class CommandFactory
{
    private readonly IKBDbSupport _support;
    private readonly Logger _logger;
    private SqlConnection _connectionString;
    private readonly string _customSchema;

    public CommandFactory(IKBDbSupport support, string customSchema, Logger logger)
    {
        _customSchema = customSchema;
        _support = support;
        _logger = logger;
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

    // --- Example: Read ---
    internal DataTable GetMyData(int accountKey)
    {
        _logger.Information("Starting GetMyData()");
        var retVal = new DataTable();
        try
        {
            using (var conn = GetDbConnection())
            {
                var parameters = new DynamicParameters();
                parameters.Add("AccountDBKey", accountKey, dbType: DbType.Int32);
                retVal.Load(conn.ExecuteReader(
                    $"{_customSchema}.cx_myfeature_get",  // ckbcustom.cx_myfeature_get
                    parameters,
                    commandType: CommandType.StoredProcedure));
                ConnectionCleanup(conn);
            }
        }
        catch (Exception ex) { _logger.Error(ex, "GetMyData Exception"); }
        _logger.Information("Finished GetMyData()");
        return retVal;
    }

    // --- Example: Write ---
    internal void SaveMyData(int accountKey, string name)
    {
        _logger.Information("Starting SaveMyData()");
        try
        {
            using (var conn = GetDbConnection())
            {
                var parameters = new DynamicParameters();
                parameters.Add("AccountDBKey", accountKey, dbType: DbType.Int32);
                parameters.Add("Name", name, dbType: DbType.String, size: 100);
                conn.Execute(
                    $"{_customSchema}.cx_myfeature_save",  // ckbcustom.cx_myfeature_save
                    parameters,
                    commandType: CommandType.StoredProcedure);
                ConnectionCleanup(conn);
            }
        }
        catch (Exception ex) { _logger.Error(ex, "SaveMyData Exception"); }
        _logger.Information("Finished SaveMyData()");
    }

    // --- Example: JSON round-trip ---
    internal string GetJsonData(int key)
    {
        _logger.Information("Starting GetJsonData()");
        var retVal = string.Empty;
        try
        {
            using (var conn = GetDbConnection())
            {
                var parameters = new DynamicParameters();
                parameters.Add("DBKey", key, dbType: DbType.Int32);
                retVal = conn.ExecuteScalar(
                    $"{_customSchema}.cx_myfeature_json_get",  // ckbcustom.cx_myfeature_json_get
                    parameters,
                    commandType: CommandType.StoredProcedure)?.ToString();
                ConnectionCleanup(conn);
            }
        }
        catch (Exception ex) { _logger.Error(ex, "GetJsonData Exception"); }
        _logger.Information("Finished GetJsonData()");
        return retVal;
    }
    
    // --- GetPageKey: resolve an OA page key by name ---
    // SP: ckbcustom.cx_page_key_get
    internal string GetPageKey(string pageName)
    {
        _logger.Information($"Starting GetPageKey() pageName={pageName}");
        var retVal = string.Empty;
        try
        {
            using (var conn = GetDbConnection())
            {
                var p = new DynamicParameters();
                p.Add("Name", pageName, dbType: DbType.String, size: 200);
                retVal = conn.ExecuteScalar<string>(
                    $"{_customSchema}.cx_page_key_get",
                    p,
                    commandType: CommandType.StoredProcedure) ?? string.Empty;
                ConnectionCleanup(conn);
            }
        }
        catch (Exception ex) { _logger.Error(ex, "GetPageKey Exception"); }
        _logger.Information($"Finished GetPageKey() retVal={retVal}");
        return retVal;
    }
}
```

---

## ConfigurationHelper Pattern

```csharp
using System.Configuration;
using System.IO;
using System.Web;
using Serilog;
using Serilog.Extras.Web;

public static class ConfigurationHelper
{
    public static string GetConfigSetting(string settingName)
    {
        AppSettingsSection section = null;
        try
        {
            var path = HttpContext.Current.Request.MapPath("~/Custom/Config/CXCustomizations.config");
            if (File.Exists(path))
            {
                var map = new ExeConfigurationFileMap { ExeConfigFilename = path };
                section = (AppSettingsSection)ConfigurationManager
                    .OpenMappedExeConfiguration(map, ConfigurationUserLevel.None)
                    .GetSection("appSettings");
            }
        }
        catch (Exception ex)
        {
            // log if logger available, or swallow — config read failure is surfaced at call site
        }
        return section?.Settings[settingName]?.Value;
    }

    public static Logger CreateLogger(string featureName)
    {
        var logDir = HttpContext.Current.Server.MapPath($"~/Logging/{featureName}/");
        if (!Directory.Exists(logDir))
            Directory.CreateDirectory(logDir);

        return new LoggerConfiguration()
            .WriteTo.RollingFileAlternate(
                logDir,
                logFilePrefix: $"{Helper.CurrentUser?.Replace('\\', '-') ?? "UnknownUser"}",
                minimumLevel: Serilog.Events.LogEventLevel.Debug,
                outputTemplate: "{Timestamp:MM-dd-yyyy HH:mm:ss} [{Level}] {Message}{NewLine}{Exception}",
                fileSizeLimitBytes: 1048576 / 8,
                retainedFileCountLimit: 1)
            .CreateLogger();
    }
}
```

---

## Planogram Selection Pattern — Multi-select

Use when the user needs to pick one or more planograms from the standard OA hierarchy/explorer UI.
Results arrive as a `#`-delimited list of DBKeys via `PublishedKey.JsDBKeyList`.

### Step 1 — Constructor Subscriptions

```csharp
public MyControlUI() : base()
{
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.HierarchyDBKeyList);
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.JsDBKeyList);
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBStatusList);
}
```

### Step 2 — ASCX Markup

```aspx
<asp:LinkButton ID="lnkbtnSelectPlanogram" CommandName="ObjectExplorerSpace"
    OnClick="PlanogramList_ButtonClick" CssClass="link-button-icon-label">
    <asp:Label ID="lblSelectPlanogram" Text="Select Planogram(s)" />
</asp:LinkButton>
```

### Step 3 — Class Declaration

```csharp
public partial class MyControlUI : UserControlBase, IPopupControlSubscriber, ICommandManager
```

### Step 4 — Open the Popup

```csharp
protected void PlanogramList_ButtonClick(object sender, EventArgs e)
{
    switch (((LinkButton)sender).CommandName)
    {
        case "ObjectExplorerSpace":
            var pageKey = _commandFactory.GetPageKey("CKB Multi-select Planogram Explorer");
            var popupPageEventArgs = new PopupPageEventArgs
            {
                PageKey = pageKey,
                Title = "Select Planogram(s)",
                AutoHeight = true,
                HideControlTitle = true,
                HidePageTitle = true,
                Buttons = PopupButtons.OkCancel,
            };
            OnDisplayPopupPage(popupPageEventArgs);
            break;
    }
}
```

### Step 5 — Receive Results

```csharp
public void Receive(PopupControlEventArgs eventArgs)
{
    _logger.Information($"Receive() key: {eventArgs.Key} value: {eventArgs.ReturnValue}");

    switch (eventArgs.Key)
    {
        case PublishedKey.JsDBKeyList:  // multi-select, values delimited by '#'
            var dt = new DataTable();
            dt.Columns.Add("pogKey");
            foreach (var item in eventArgs.ReturnValue.ToString().Trim()
                .Split(new char[] { '#' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var row = dt.NewRow();
                row[0] = item;
                dt.Rows.Add(row);
            }
            _uiModel.SelectionModel.PogKeys = dt;
            break;

        case PublishedKey.DBStatusList:
            var statusDt = new DataTable();
            statusDt.Columns.Add("statusKey");
            foreach (var item in eventArgs.ReturnValue.ToString().Trim()
                .Split(new char[] { '#' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var row = statusDt.NewRow();
                row[0] = item;
                statusDt.Rows.Add(row);
            }
            _uiModel.SelectionModel.StatusKeys = statusDt;
            break;
    }

    // Persist updated model back to session
    var json = JsonConvert.SerializeObject(_uiModel);
    SubscriptionManager.Publish(this, CommonConstants.SESSION_UIModel, json);
}
```

---

## Planogram Selection Pattern — Single-select

Use when the user needs to pick exactly one planogram. Uses the built-in `"CKB Planogram Explorer"`
page (no multi-select). Result arrives as a single integer via `PublishedKey.DBKey`.

> **Note:** `"CKB Planogram Explorer"` publishes `PublishedKey.DBKey` (a plain integer), not
> `JsDBKeyList`. Subscribe to and guard on `DBKey` only — no `#`-split needed.

### Step 1 — Constructor Subscriptions

```csharp
public MyControlUI() : base()
{
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBKey);
    SubscriptionManager.AddKeyToPublish(CommonConstants.SESSION_SelectedPogKey);
}
```

### Step 2 — ASCX Markup

```aspx
<asp:LinkButton runat="server" ID="lnkSelectPog" Text="Select Planogram"
    OnClick="lnkSelectPog_Click" />
```

### Step 3 — Class Declaration

```csharp
public partial class MyControlUI : UserControlBase, IPopupControlSubscriber, ICommandManager
```

### Step 4 — Open the Popup

```csharp
protected void lnkSelectPog_Click(object sender, EventArgs e)
{
    var pageKey = _commandFactory.GetPageKey("CKB Planogram Explorer");
    OnDisplayPopupPage(new PopupPageEventArgs
    {
        PageKey          = pageKey,
        Title            = "Select Planogram",
        AutoHeight       = true,
        HideControlTitle = true,
        HidePageTitle    = true,
        Buttons          = PopupButtons.OkCancel,
    });
}
```

### Step 5 — Receive Results

```csharp
public void Receive(PopupControlEventArgs e)
{
    _logger.Information($"Receive() key: {e.Key} value: {e.ReturnValue}");

    if (e.Key != PublishedKey.DBKey) return;

    var pogKey = Convert.ToInt32(e.ReturnValue?.ToString());
    if (pogKey <= 0) return;

    var info = _commandFactory.GetPlanogramInfo(pogKey);
    if (info == null) return;

    _uiModel.PogDBKey  = pogKey;
    _uiModel.PogName   = info.Name;
    _uiModel.Status    = info.Status1;
    _uiModel.CurrentStores = _commandFactory.GetPlanogramStores(pogKey).ToList();
    _uiModel.NewStores     = new List<StoreAssignment>();

    // Publish JSON snapshot so refresh can restore without a DB call
    SubscriptionManager.Publish(this, CommonConstants.SESSION_SelectedPogKey,
        JsonConvert.SerializeObject(_uiModel));
    PublishModel();
}
```

---

## Standalone Control (UserControlBase)

Full scaffold for a new ASCX-based UI control.

```csharp
using System;
using System.Collections.Generic;
using System.Web.UI.WebControls;
using Newtonsoft.Json;
using Serilog;

public partial class MyFeatureUI : UserControlBase, ICommandManager, IPopupControlSubscriber
{
    private static readonly Logger _logger = ConfigurationHelper.CreateLogger("MyFeature");
    private CommandFactory _commandFactory;
    private MyFeatureModel _uiModel;

    protected override void OnInit(EventArgs e)
    {
        base.OnInit(e);

        // Wire up subscription keys
        SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBKey);
        SubscriptionManager.AddKeyToPublish("_updated");
    }

    protected override void OnLoad(EventArgs e)
    {
        _logger.Information("Starting OnLoad()");
        base.OnLoad(e);

        var customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");
        _commandFactory = new CommandFactory(KBDbSupport, customSchema, _logger);

        if (!IsPostBack)
        {
            LoadUI();
        }
        _logger.Information("Finished OnLoad()");
    }

    private void LoadUI()
    {
        _logger.Information("Starting LoadUI()");
        var accountKey = Convert.ToInt32(
            SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey));
        
        _uiModel = new MyFeatureModel { AccountKey = accountKey };
        var data = _commandFactory.GetMyData(accountKey);
        // bind data to controls...
        _logger.Information("Finished LoadUI()");
    }

    // ICommandManager
    public List<CommandAction> GetCommands()
    {
        return new List<CommandAction>
        {
            new CommandAction()
            {
                Command = "Save",
                Tooltip = "Save",
                ImageCss = StyleSelectors.ImageProcessOneBlue,
                CommandLocation = CommandLocations.TopRight,
                Enabled = true,
                Visible = true,
                RequiresPostBack = false,
            }
        };
    }

    public void DoCommand(CommandEventArgs e)
    {
        try
        {
            switch (e.CommandName)
            {
                case "Save":
                    _commandFactory.SaveMyData(_uiModel.AccountKey, txtName.Text);
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

    // IPopupControlSubscriber — omit if no popup selection needed
    public void Receive(PopupControlEventArgs eventArgs)
    {
        _logger.Information($"Receive() key: {eventArgs.Key}");
        // handle popup results (see Planogram Selection Pattern above)
    }

    protected override void OnMessageReceived(object sender, DataStoreChangedEventArgs e)
    {
        if (e.Key.Equals(SubscriptionManager.SubscribedKey(PublishedKey.DBKey),
                         StringComparison.OrdinalIgnoreCase))
        {
            LoadUI();
        }
    }
}
```

---

## Derived Grid Control

For extending an existing OA grid class with custom commands or filtering.

**Base class selection:**
| Use case | Base class |
|---|---|
| Generic grid with custom commands | `AdvancedTableGrid` |
| Planogram lifecycle grid (version/copy/promote) | `LifecycleGrid` |
| Dictionary-style grid | `AdvancedDictionaryGrid` |

**Required usings:**
```csharp
using JDA.Intactix.Common;
using JDA.Intactix.IKB.Web.Framework;
using JDA.Intactix.IKB.Web.UI.WebControls;
using JDA.Intactix.Web.Common;
using JDA.Intactix.Web.Framework;
using JDA.Intactix.Web.Framework.Common;

using System;
using System.Collections.Generic;
using System.Web.UI.WebControls;
```

**Scaffold:**
```csharp
#region
using JDA.Intactix.Common;
using JDA.Intactix.IKB.Web.Framework;
using JDA.Intactix.IKB.Web.UI.WebControls;
using JDA.Intactix.Web.Common;
using JDA.Intactix.Web.Framework;
using JDA.Intactix.Web.Framework.Common;

using MyProject.HelperClasses;

using Serilog.Core;

using System;
using System.Collections.Generic;
using System.Web.UI.WebControls;
#endregion

public class CXMyDerivedGrid : LifecycleGrid, ICommandManager   // or AdvancedTableGrid
{
    private static readonly Logger _logger = ConfigurationHelper.CreateLogger("MyDerivedGrid");
    private CommandFactory _commandFactory;

    public CXMyDerivedGrid()
    {
        SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBKey);
        // Do NOT AddKeyToPublish("_updated") here — popup views own that signal
    }

    protected override void OnLoad(EventArgs e)
    {
        _logger.Information("Starting OnLoad()");
        base.OnLoad(e);
        var customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");
        _commandFactory  = new CommandFactory(KBDbSupport, customSchema, _logger);
        _logger.Information("Finished OnLoad()");
    }

    protected override void OnMessageReceived(object sender, DataStoreChangedEventArgs e)
    {
        if (e.Key.Equals(SubscriptionManager.SubscribedKey(PublishedKey.DBKey),
                         StringComparison.OrdinalIgnoreCase))
        {
            var key = SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey);
            if (!string.IsNullOrEmpty(key))
            {
                Filter            = $"DBParentKey = {key}";
                CurrentPageNumber = 0;
                OnControlChanged(new ControlChangedEventArgs());
                base.Refresh();
            }
        }
    }

    public List<CommandAction> GetCommands()
    {
        return new List<CommandAction>
        {
            new CommandAction()
            {
                Command          = "CustomAction",
                Tooltip          = "Do Custom Action",
                ImageCss         = StyleSelectors.ImageProcessOneBlue,
                CommandLocation  = CommandLocations.TopRight,
                Enabled          = true,
                Visible          = true,
                RequiresPostBack = false,
            }
        };
    }

    public void DoCommand(CommandEventArgs e)
    {
        _logger.Information($"Starting DoCommand() command={e.CommandName}");
        try
        {
            switch (e.CommandName)
            {
                case "CustomAction":
                    var key = SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey);
                    _commandFactory.SaveMyData(Convert.ToInt32(key), "value");
                    SubscriptionManager.Publish(this, "_updated", 1);
                    break;
            }
        }
        catch (Exception ex) { _logger.Error(ex, "DoCommand Exception"); }
        _logger.Information("Finished DoCommand()");
    }
}
```

---

## Job Queue Pattern

Long-running operations (copy, version, promote, demote) always insert a row into
`ckbcustom.cx_job` with the model serialized as JSON. This provides a tracking record
regardless of how the job is processed.

**Deployment mode** controls whether the process proc is called immediately or deferred
to a background service:

| Mode | Submit behavior |
|---|---|
| `OnPrem` | Insert job → service polls `cx_job` and calls the process proc |
| `SaaS` | Insert job → immediately call process proc in the same web request |

Set in `~/Custom/Config/CXCustomizations.config`:
```xml
<add key="DeploymentMode" value="SaaS" />   <!-- or "OnPrem" -->
```

### Table (`SQL/Tables/ckbcustom.cx_job.sql`)

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

### SP (`SQL/Stored Procedures/ckbcustom.cx_job_ins.sql`)

`cx_job_ins` inserts the job and returns the new row's DBKey via `SCOPE_IDENTITY()`.
The C# caller captures this key and passes it to the process proc (SaaS path).

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

### SP (`SQL/Stored Procedures/ckbcustom.cx_<feature>_process.sql`)

The process proc accepts an optional `@job_dbkey`. When called with a key (SaaS), it
processes that one job. When called with no key (OnPrem background service), it loops
all `Submitted` jobs of the matching type.

After a successful commit, the proc sets `Status = 'Completed'` on the job row.

```sql
CREATE OR ALTER PROCEDURE ckbcustom.cx_<feature>_process
    @job_dbkey INT = NULL   -- NULL = OnPrem service path (all Submitted); value = SaaS single job
AS
BEGIN
    SET NOCOUNT ON;

    -- OnPrem service path: loop every Submitted job
    IF @job_dbkey IS NULL
    BEGIN
        DECLARE @cur_key INT;
        DECLARE job_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DBKey
            FROM   ckbcustom.cx_job
            WHERE  JobType = '<feature>'       -- match the jobType string used in cx_job_ins
              AND  Status  = 'Submitted'
            ORDER BY DBKey;

        OPEN job_cursor;
        FETCH NEXT FROM job_cursor INTO @cur_key;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC ckbcustom.cx_<feature>_process @job_dbkey = @cur_key;
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
        THROW 50000, 'cx_<feature>_process: Job not found or has no parameters.', 1;

    -- ... feature-specific logic here ...

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ... do the work ...

        COMMIT TRANSACTION;

        -- Mark job complete after successful commit
        UPDATE ckbcustom.cx_job
        SET    Status = 'Completed'
        WHERE  DBKey  = @job_dbkey;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
GRANT EXECUTE ON ckbcustom.cx_<feature>_process TO public;
```

### CommandFactory methods

```csharp
// Read once per request — call from OnInit and store on the control
internal bool IsSaaS()
{
    var mode = ConfigurationHelper.GetConfigSetting("DeploymentMode") ?? string.Empty;
    _logger.Information($"IsSaaS: DeploymentMode='{mode}'");
    return string.Equals(mode, "SaaS", StringComparison.OrdinalIgnoreCase);
}

// Returns the new job's DBKey — pass to ProcessJob on the SaaS path
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
                $"{_customSchema}.cx_job_ins", p, commandType: CommandType.StoredProcedure);
            ConnectionCleanup(conn);
            _logger.Information($"Finished InsertJob() jobDbKey={jobDbKey}");
            return jobDbKey;
        }
    }
    catch (Exception ex) { _logger.Error(ex, "InsertJob Exception"); }
    return 0;
}

// SaaS on-demand processing — pass the DBKey returned by InsertJob
// The proc fetches JSON from cx_job itself and sets Status='Completed' on success
internal void ProcessJob(int jobDbKey)
{
    _logger.Information($"Starting ProcessJob() jobDbKey={jobDbKey}");
    try
    {
        using (var conn = GetDbConnection())
        {
            var p = new DynamicParameters();
            p.Add("job_dbkey", jobDbKey, dbType: DbType.Int32);
            conn.Execute($"{_customSchema}.cx_<feature>_process", p,
                commandType: CommandType.StoredProcedure);
            ConnectionCleanup(conn);
        }
    }
    catch (Exception ex) { _logger.Error(ex, "ProcessJob Exception"); }
    _logger.Information("Finished ProcessJob()");
}
```

Requires `using Newtonsoft.Json;` in CommandFactory.
Replace `cx_<feature>_process` with the actual process proc name (e.g. `cx_pog_split_process`).

### Calling from Submit (both deployment modes)

```csharp
private void Submit()
{
    SyncModelFromHiddenField();
    PublishModel();

    // validate ...

    var isSaaS   = _commandFactory.IsSaaS();
    var jobDbKey = _commandFactory.InsertJob(_uiModel, Helper.CurrentUser, "POG Split");

    if (isSaaS)
    {
        // SaaS: no background service — process immediately using the inserted job's key
        _commandFactory.ProcessJob(jobDbKey);
    }
    // OnPrem: background service calls cx_<feature>_process with no params to process all Submitted jobs

    _uiModel = new MyFeatureModel();
    SubscriptionManager.Publish(this, CommonConstants.SESSION_SelectedPogKey, string.Empty);
    PublishModel();

    OnDisplayMessage(new MessageEventArgs()
    {
        Message          = isSaaS
            ? "Operation completed successfully."
            : "Job submitted successfully.",
        EventType        = MessageEventTypes.Success,
        MessageLocation  = MessageLocations.BottomLeft
    });
}
```

---

## Opening a Custom ASCX Popup

Use `ControlTemplate` — **never `PageKey`** — to open a custom `.ascx` popup from a derived grid
or UI control. `PageKey` requires the page to be registered in `ix_web_page`; `ControlTemplate`
resolves the `.ascx` file directly from `~/Custom/` and works without page registration.

```csharp
var popup = new PopupPageEventArgs
{
    ControlTemplate  = new ControlTemplate { ControlType = "ascx", Name = "MyPopupUI", Path = "~/Custom" },
    Title            = "My Popup",
    AutoHeight       = true,
    HideControlTitle = true,
    HidePageTitle    = true,
    Buttons          = PopupButtons.None,
};
popup.AddParameter("ObjectKeys", objectKeys);
popup.AddParameter("NodeKeys",   nodeKeys);
popup.AddParameter("StatusKeys", statusKeys);
OnDisplayPopupPage(popup);
```

`ControlTemplate.Name` must match the deployed `.ascx` filename (without extension).

### Reading parameters inside the popup view

`AddParameter` stores values in `HttpContext.Current.Items`. Read them in `Page_Load` / `OnLoad`:

```csharp
// In the popup view's OnLoad / LoadUI — NOT via SubscriptionManager
var rawKeys = Context.Items["ObjectKeys"]?.ToString() ?? string.Empty;
```

**Never** use `SubscriptionManager.GetPageStoreData(this, PublishedKey.JsDBKeyList)` inside a
popup view to get the caller's selection — those values are not forwarded into the popup context.

### Subscription keys in popup views

Popup views only need to publish `"_updated"` so the parent grid can refresh after submit.
They do **not** need to subscribe to `JsDBKeyList` or any grid key:

```csharp
protected override void OnInit(EventArgs e)
{
    base.OnInit(e);
    SubscriptionManager.AddKeyToPublish("_updated");
    // No AddKeyToSubscribe needed — use Context.Items for input data
}
```

---

## Fieldset Group Box Pattern

Use `<fieldset>` + `<legend>` to visually group sections of a standalone control. This is the
standard OA pattern (from `FpCopyVersion.ascx`, `PogCopyVersion.ascx`).

### ASCX markup

```aspx
<fieldset>
    <legend>
        <asp:Label runat="server" Text=" Section Title "
            Font-Size="14px" Font-Names="Segoe UI Semibold"
            BackColor="Transparent" ForeColor="Black" Font-Bold="false" />
    </legend>
    <asp:Panel runat="server" CssClass="hostPanel">
        <%-- form content: asp:Table, asp:ListBox, etc. --%>
    </asp:Panel>
</fieldset>
```

- The legend label uses inline attributes (not a CSS class) so the style is self-contained
- Spaces around the title text (` Section Title `) provide visual padding inside the legend box
- `<asp:Panel>` renders as `<div>` — use `CssClass="hostPanel"` for consistent inner padding
- Multiple fieldsets stack with `style="margin-top:12px;"` on the second and subsequent ones

### CSS

```css
.hostPanel { padding: 8px 4px; }
```

No explicit `fieldset` or `legend` CSS is needed — browser defaults render the border and
legend overlay correctly.

### ASP server controls for tables

Use `<asp:Table>`, `<asp:TableRow>`, `<asp:TableCell>` instead of raw HTML `<table>/<tr>/<td>`
inside fieldsets to stay consistent with the ASP server-control model:

```aspx
<asp:Table runat="server">
    <asp:TableRow runat="server">
        <asp:TableCell runat="server" style="padding-right:8px;">
            <asp:Label runat="server" Text="Field:" />
        </asp:TableCell>
        <asp:TableCell runat="server">
            <asp:TextBox runat="server" ID="txtField" CssClass="txt" />
        </asp:TableCell>
    </asp:TableRow>
</asp:Table>
```

**TextBox CSS:** Use `CssClass="txt"` with `.txt { width: Xpx; }` only — no font or border
overrides. The OA framework stylesheet provides the base input appearance.

### Client-side-only buttons

Use `<asp:Button>` with **both** `UseSubmitBehavior="false"` and `OnClientClick="return false;"`.

- `UseSubmitBehavior="false"` renders `<input type="button">` with `onclick="__doPostBack(...)"`.
- `OnClientClick="return false;"` is prepended to the onclick, making it
  `onclick="return false;__doPostBack(...)"`. The `return false` exits before `__doPostBack` runs,
  so no postback occurs.
- jQuery's `.on('click')` is a separate event listener registered independently — it fires
  regardless of what the inline onclick returns.
- `ClientIDMode="Static"` ensures the rendered ID matches what the external JS file references.

```aspx
<asp:Button runat="server" ID="btnAction" Text="Do Thing" CssClass="cx-btn"
    UseSubmitBehavior="false" OnClientClick="return false;" ClientIDMode="Static" />
```

```javascript
$('#btnAction').on('click', function () { /* client-only work */ });
```

Declare the button in `designer.cs`:

```csharp
protected Button btnAction;
```

---

## JSON Snapshot Refresh Pattern

When a user selects a planogram (or any item) and the page may be refreshed, store a JSON
snapshot of the full selection state in a named session key. On refresh, `OnInit` deserializes
the snapshot instead of hitting the database again.

### CommonConstants

```csharp
public const string SESSION_UIModel        = "SESSION_UIModel";
public const string SESSION_SelectedPogKey = "SESSION_SelectedPogKey";
```

### Constructor

```csharp
public MyControlUI() : base()
{
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBKey);
    SubscriptionManager.AddKeyToPublish(CommonConstants.SESSION_SelectedPogKey);
}
```

### OnInit — clear on fresh load, restore from snapshot on postback

```csharp
protected override void OnInit(EventArgs e)
{
    base.OnInit(e);
    _customSchema   = ConfigurationHelper.GetConfigSetting("CustomSchema");
    _commandFactory = new CommandFactory(_dbSupport, _customSchema, _logger);

    if (!Page.IsPostBack)
    {
        _uiModel = new POGSplitModel();
        SubscriptionManager.Publish(this, CommonConstants.SESSION_SelectedPogKey, string.Empty);
        PublishModel();
        return;
    }

    var json = SubscriptionManager.GetPageStoreData(this, CommonConstants.SESSION_UIModel)?.ToString();
    _uiModel = string.IsNullOrEmpty(json)
        ? new MyFeatureModel()
        : JsonConvert.DeserializeObject<MyFeatureModel>(json);

    // Fallback: restore from snapshot if UIModel was lost (e.g. session expiry + refresh)
    if (_uiModel.PogDBKey <= 0)
    {
        var snapshot = SubscriptionManager.GetPageStoreData(this, CommonConstants.SESSION_SelectedPogKey)?.ToString();
        if (!string.IsNullOrEmpty(snapshot))
            _uiModel = JsonConvert.DeserializeObject<MyFeatureModel>(snapshot) ?? _uiModel;
    }
}
```

### Receive — publish full model as JSON snapshot

```csharp
// After populating _uiModel from the selection:
SubscriptionManager.Publish(this, CommonConstants.SESSION_SelectedPogKey,
    JsonConvert.SerializeObject(_uiModel));
PublishModel();
```

### Submit / clear — publish empty string to invalidate snapshot

```csharp
_uiModel = new MyFeatureModel();
SubscriptionManager.Publish(this, CommonConstants.SESSION_SelectedPogKey, string.Empty);
PublishModel();
```

---

## SessionHelper Pattern

Use when a control needs typed access to session data outside of SubscriptionManager publishing.

```csharp
public static class SessionHelper
{
    private const string _key = CommonConstants.SESSION_UIModel;

    public static MyFeatureModel GetModel()
    {
        if (HttpContext.Current.Session[_key] != null)
            return HttpContext.Current.Session[_key] as MyFeatureModel;
        return new MyFeatureModel();
    }

    public static void SetModel(MyFeatureModel value)
    {
        HttpContext.Current.Session[_key] = value;
    }

    public static void ClearModel()
    {
        HttpContext.Current.Session.Remove(_key);
    }
}
```

---

## Model Classes

```csharp
// Main UI model — serialized to JSON for session/database storage
public class MyFeatureModel
{
    public int AccountKey { get; set; }
    public string Username { get; set; }
    public string Status { get; set; }
    public PlanogramSelectionModel SelectionModel { get; set; } = new PlanogramSelectionModel();
}

// Planogram selection sub-model — used when popup selection is involved
public class PlanogramSelectionModel
{
    public DataTable PogKeys { get; set; }      // Selected planogram DBKeys
    public DataTable StatusKeys { get; set; }   // Selected status keys
    public DataTable NodeKeys { get; set; }     // Hierarchy node selections
}
```

---

## Standalone Control — Model Lifecycle Pattern

Use this lifecycle in any standalone control that maintains state across postbacks
(store assignments, selection state, multi-step workflows). The model lives in
`SubscriptionManager` session as JSON; `OnInit` loads it, `OnPreRender` binds from it,
every state-changing handler publishes it back.

This pattern avoids `Page_Load` / `!IsPostBack` sprawl and ensures the model is always
the single source of truth for what is displayed.

```csharp
public partial class MyFeatureUI : UserControlBase, ICommandManager, IPopupControlSubscriber
{
    private static readonly Logger _logger = ConfigurationHelper.CreateLogger("MyFeature");

    private CommandFactory  _commandFactory;
    private MyFeatureModel  _uiModel;
    private string          _customSchema;

    // ─── Constructor ────────────────────────────────────────────────────────
    // Wire subscriptions HERE — not in OnInit — so the framework registers
    // them before the page lifecycle resolves published keys.

    public MyFeatureUI() : base()
    {
        SubscriptionManager.AddKeyToSubscribe(CommonConstants.SESSION_SelectedKey);
    }

    // ─── OnInit: load dependencies and deserialize model ────────────────────

    protected override void OnInit(EventArgs e)
    {
        base.OnInit(e);
        _customSchema   = ConfigurationHelper.GetConfigSetting("CustomSchema");
        _commandFactory = new CommandFactory(IKBDbSupport, _customSchema, _logger);

        var json = SubscriptionManager.GetPageStoreData(this, CommonConstants.SESSION_UIModel)?.ToString();
        _uiModel = string.IsNullOrEmpty(json)
            ? new MyFeatureModel()
            : JsonConvert.DeserializeObject<MyFeatureModel>(json);
    }

    // ─── OnPreRender: bind all controls from model ───────────────────────────
    // Runs AFTER all event handlers (button clicks, Receive, DoCommand).
    // Only set text inputs on !IsPostBack to avoid overwriting user edits.

    protected override void OnPreRender(EventArgs e)
    {
        base.OnPreRender(e);
        lblStatus.Text = _uiModel.StatusText ?? string.Empty;

        if (!Page.IsPostBack)
            txtName.Text = _uiModel.Name ?? string.Empty;

        // Bind read-only displays unconditionally
        gvItems.DataSource = _uiModel.Items;
        gvItems.DataBind();
    }

    // ─── PublishModel: always call after mutating _uiModel ──────────────────

    private void PublishModel()
    {
        SubscriptionManager.Publish(this, CommonConstants.SESSION_UIModel,
            JsonConvert.SerializeObject(_uiModel));
    }
}
```

**Key rules:**
- `AddKeyToSubscribe` / `AddKeyToPublish` in the **constructor**, not `OnInit`
- Load model in `OnInit` (IKBDbSupport is available there)
- Bind controls in `OnPreRender` — it runs after every event handler
- Set `TextBox` values only on `!Page.IsPostBack` to preserve user edits
- Call `PublishModel()` after every state change so session stays in sync

---

## Custom Single-Select Popup (IPopupCommandManager)

Use this pattern when building a custom ASCX popup that lets the user pick exactly one
item (e.g., a single planogram, a single template) and return the selection to the parent.

This differs from the built-in OA multi-select explorer — the built-in returns
`PublishedKey.JsDBKeyList`; a custom single-select popup uses a named session key.

### Popup view (the control being opened)

```csharp
public partial class MySelectUI : UserControlBase, IPopupCommandManager
{
    private static readonly Logger _logger = ConfigurationHelper.CreateLogger("MySelect");
    private CommandFactory _commandFactory;

    // Register the key this popup will publish before the page resolves keys
    public MySelectUI() : base()
    {
        SubscriptionManager.AddKeyToPublish(CommonConstants.SESSION_SelectedKey);
    }

    protected override void OnInit(EventArgs e)
    {
        base.OnInit(e);
        _commandFactory = new CommandFactory(
            IKBDbSupport,
            ConfigurationHelper.GetConfigSetting("CustomSchema"),
            _logger);
    }

    protected override void OnPreRender(EventArgs e)
    {
        base.OnPreRender(e);
        // Bind the selection grid/list every render so DataKeys are always populated
        gvItems.DataSource = _commandFactory.GetBrowseItems();
        gvItems.DataBind();
    }

    protected void gvItems_SelectedIndexChanged(object sender, EventArgs e) { }

    // ─── IPopupCommandManager ────────────────────────────────────────────────

    // Called when user clicks the popup's OK button
    public void ExecuteCommandOnPopupOK()
    {
        if (gvItems.SelectedIndex < 0) return;

        var dbKey = gvItems.DataKeys[gvItems.SelectedIndex]?.Value?.ToString();
        if (!string.IsNullOrEmpty(dbKey))
            SubscriptionManager.Publish(this, CommonConstants.SESSION_SelectedKey, dbKey);
    }

    public void ExecuteCommandOnPopupClose() { }
}
```

**ASCX for the popup:**

```aspx
<%@ Control Language="C#" AutoEventWireup="true"
    CodeBehind="MySelectUI.ascx.cs" Inherits="MyProject.Views.MySelectUI" %>

<asp:GridView runat="server" ID="gvItems"
    DataKeyNames="DBKey"
    AutoGenerateColumns="False"
    CssClass="cx-grid"
    EmptyDataText="No items found."
    OnSelectedIndexChanged="gvItems_SelectedIndexChanged">
    <Columns>
        <asp:CommandField ShowSelectButton="True" SelectText="Select" />
        <asp:BoundField DataField="Name"   HeaderText="Name" />
        <asp:BoundField DataField="Status" HeaderText="Status" />
    </Columns>
    <SelectedRowStyle CssClass="cx-selected-row" />
</asp:GridView>
```

### Parent control (the control opening the popup)

```csharp
public partial class MyFeatureUI : UserControlBase, ICommandManager, IPopupControlSubscriber
{
    // Subscribe in constructor so the framework wires it up before page lifecycle
    public MyFeatureUI() : base()
    {
        SubscriptionManager.AddKeyToSubscribe(CommonConstants.SESSION_SelectedKey);
    }

    // Open the popup via ControlTemplate (no ix_web_page registration needed)
    protected void lnkSelectItem_Click(object sender, EventArgs e)
    {
        OnDisplayPopupPage(new PopupPageEventArgs
        {
            ControlTemplate = new ControlTemplate
            {
                ControlType = "ascx",
                Name        = "MySelectUI",   // filename without extension
                Path        = "~/Custom"
            }
        });
    }

    // Receive the published key when the popup's OK is clicked
    public void Receive(PopupControlEventArgs e)
    {
        if (e.Key != CommonConstants.SESSION_SelectedKey) return;

        var dbKey = Convert.ToInt32(e.ReturnValue);
        if (dbKey <= 0) return;

        // Load data for the selected item, update model, publish
        var info = _commandFactory.GetItemInfo(dbKey);
        if (info == null) return;

        _uiModel.SelectedKey  = dbKey;
        _uiModel.SelectedName = info.Name;
        PublishModel();
    }
}
```

**CommonConstants.cs — define session keys here:**

```csharp
public static class CommonConstants
{
    public const string SESSION_UIModel      = "SESSION_UIModel";
    public const string SESSION_SelectedKey  = "SESSION_SelectedKey";
}
```

---

## Client-side ListBox Transfer Pattern

Use this pattern when the user needs to move items between two lists without causing
postbacks. Move buttons use `<button type="button">` (or jQuery `e.preventDefault()`)
so no form submission occurs. A hidden field tracks the state of the destination list;
the server reads it on the next real postback (Submit).

Source: `OA Derived Controls\Javascript\OAControls.js` in the Acosta project.

### ASCX markup

```aspx
<%-- Source and destination ListBoxes --%>
<asp:ListBox runat="server" ID="lbSource"
    SelectionMode="Multiple" Rows="15" Width="220px" CssClass="cx-listbox" />

<%-- Plain HTML buttons — type="button" prevents form submission --%>
<button type="button" id="btnMoveToDest"  class="cx-btn">Move &rarr;</button>
<button type="button" id="btnMoveToSrc"   class="cx-btn">&larr; Move</button>

<asp:ListBox runat="server" ID="lbDest"
    SelectionMode="Multiple" Rows="15" Width="220px" CssClass="cx-listbox" />

<%-- Hidden field: pipe-delimited Values of whatever is in lbDest --%>
<asp:HiddenField runat="server" ID="hdnDestItems" />

<script type="text/javascript">
    (function ($) {
        $(document).ready(function () {
            var $src     = $('#<%= lbSource.ClientID %>');
            var $dest    = $('#<%= lbDest.ClientID %>');
            var $hdnDest = $('#<%= hdnDestItems.ClientID %>');

            function sortListbox($list) {
                var opts = $list.find('option').get();
                opts.sort(function (a, b) { return $(a).val() < $(b).val() ? -1 : 1; });
                $list.empty().append(opts);
            }

            function updateHiddenField() {
                var vals = [];
                $dest.find('option').each(function () { vals.push($(this).val()); });
                $hdnDest.val(vals.join('|'));
            }

            function moveItems($from, $to) {
                var $sel = $from.find('option:selected').detach();
                if ($sel.length === 0) return;
                $to.append($sel);
                $sel.prop('selected', false);
                sortListbox($from);
                sortListbox($to);
                updateHiddenField();
            }

            $('#btnMoveToSrc').on('click',  function () { moveItems($dest, $src);  });
            $('#btnMoveToDest').on('click', function () { moveItems($src,  $dest); });
        });
    }(jQuery));
</script>
```

### Designer.cs

```csharp
public partial class MyFeatureUI
{
    protected ListBox     lbSource;
    protected ListBox     lbDest;
    protected HiddenField hdnDestItems;
    // No server-side button declarations — buttons are plain HTML
}
```

### Code-behind: bind and sync

**In `OnPreRender`** — bind both lists from the model AND sync the hidden field so JS
always starts from the correct state after any postback:

```csharp
protected override void OnPreRender(EventArgs e)
{
    base.OnPreRender(e);
    BindListBox(lbSource, _uiModel.SourceItems);
    BindListBox(lbDest,   _uiModel.DestItems);

    // Keep hidden field in sync with model so JS reflects current state
    hdnDestItems.Value = string.Join("|", _uiModel.DestItems.Select(i => i.Key));
}

private void BindListBox(ListBox lb, IEnumerable<MyItem> items)
{
    lb.Items.Clear();
    foreach (var item in items)
        lb.Items.Add(new ListItem($"{item.Key} - {item.Name}", item.Key));
}
```

**In `Submit()`** — sync the model from the hidden field BEFORE validating or saving,
so the model reflects what the user arranged client-side:

```csharp
private void Submit()
{
    SyncModelFromHiddenField();
    PublishModel();   // persist synced state so re-submission after validation failure works

    // validate _uiModel.DestItems ...
    // _commandFactory.InsertJob(_uiModel, ...) ...
}

private void SyncModelFromHiddenField()
{
    var destKeys = (hdnDestItems.Value ?? string.Empty)
        .Split(new[] { '|' }, StringSplitOptions.RemoveEmptyEntries)
        .ToHashSet();

    if (!destKeys.Any()) return;

    var allItems          = _uiModel.SourceItems.Concat(_uiModel.DestItems).ToList();
    _uiModel.DestItems    = allItems.Where(i =>  destKeys.Contains(i.Key)).ToList();
    _uiModel.SourceItems  = allItems.Where(i => !destKeys.Contains(i.Key)).ToList();
}
```

**Why `SyncModelFromHiddenField` + `PublishModel` before validation:**
The user moves items with JS (no postback). On Submit, `hdnDestItems` carries the
client-side state. If validation fails and the user re-submits, the hidden field still
has the correct arrangement. Syncing to the model and publishing ensures `OnPreRender`
re-binds correctly and the session stays consistent on every postback.

---

## JavaScript File Wiring

Every standalone control that needs client-side behavior ships a dedicated JS file.
Never use inline `<script>` blocks in the ASCX — they cannot be cached, are harder to
debug, and break when server-side `<%= control.ClientID %>` expressions are needed in
a file that ASP.NET won't process.

### Why `ClientIDMode="Static"` is required

External JS files are static — ASP.NET does not process `<%= %>` expressions inside them.
Any control the JS must select by ID (`$('#myId')`) must have a predictable, stable ID.
Add `ClientIDMode="Static"` to every such control in the ASCX markup.

Controls that always need it when used with an external JS file:
- `<asp:ListBox>` used in list-transfer JS
- `<asp:HiddenField>` tracking list state
- `<asp:Button UseSubmitBehavior="false" OnClientClick="return false;">` used as client-only move buttons

### Folder and file

Place the JS file in `Javascript\MyControl.js` under the project root.

### ASCX structure

OA custom controls must have a full `<html>/<head>/<body>` document structure. The CSS link goes in `<head>` and the script tag at the bottom of `<body>`, both using relative paths (no `ResolveUrl`):

```aspx
<%@ Control Language="C#" AutoEventWireup="true" CodeBehind="MyControlUI.ascx.cs" Inherits="MyProject.Views.MyControlUI" %>

<html>
<head>
    <title>My Control</title>
    <link rel="stylesheet" type="text/css" href="custom/styles/MyControl.css" />
</head>
<body>

    <%-- control markup here --%>

    <script type="text/javascript" src="custom/scripts/MyControl.js"></script>

</body>
</html>
```

Use `<div class="hostPanel">` instead of `<asp:Panel CssClass="hostPanel">` inside fieldsets — plain `<div>` is consistent with how the other controls render the host panel.

### ASCX control attributes

```aspx
<asp:ListBox runat="server" ID="lbSource"
    SelectionMode="Multiple" Rows="15" Width="220px"
    CssClass="cx-listbox" ClientIDMode="Static" />

<asp:HiddenField runat="server" ID="hdnDestItems" ClientIDMode="Static" />

<asp:Button runat="server" ID="btnMoveToNew" Text="Move &#x2192;" CssClass="cx-btn"
    UseSubmitBehavior="false" OnClientClick="return false;" ClientIDMode="Static" />
```

### JS file structure

The OA framework loads jQuery after the page's script tags execute, so
`$(document).ready` and the `(function($){...}(jQuery))` IIFE both fail silently —
`jQuery` is undefined at that point.

Use `Sys.Application.add_load` instead. This is the ASP.NET AJAX equivalent of
`document.ready` and fires after the ScriptManager has loaded all framework scripts
including jQuery.

```javascript
console.log('[MyControl] MyControl.js loaded');   // fires immediately on file parse

Sys.Application.add_load(function () {
    console.log('[MyControl] Sys.Application.add_load fired');  // fires after jQuery ready

    var $ = jQuery;

    var $source = $('#lbSource');   // static IDs — no <%= %> needed
    var $dest   = $('#lbDest');
    var $hdn    = $('#hdnDestItems');
    var $btnNew = $('#btnMoveToNew');

    console.log('[MyControl] btnMoveToNew found:', $btnNew.length);  // 0 = ID mismatch

    $btnNew.on('click', function () {
        console.log('[MyControl] btnMoveToNew clicked');
        // ... move logic ...
        console.log('[MyControl] hdnDestItems:', $hdn.val());
    });
});
```

Keep `console.log` calls in during development — remove before production deploy.

### Registering script from code-behind

To inject a script block that is guaranteed to execute in the correct page lifecycle
position (e.g. a diagnostic log or startup init), use `ScriptManager.RegisterClientScriptBlock`
in `OnPreRender`. **Do not use `Page.ClientScript.RegisterClientScriptBlock`** — it is
silently ignored when a ScriptManager is present on the page (which the OA framework always has).

```csharp
protected override void OnPreRender(EventArgs e)
{
    base.OnPreRender(e);

    ScriptManager.RegisterClientScriptBlock(
        this,
        GetType(),
        "MyControlLoad",
        "console.log('[MyControl] control rendered');",
        true);

    // ... rest of OnPreRender
}
```

The first two arguments (`this`, `GetType()`) uniquely identify the script block so it is
only emitted once even when the control appears multiple times on a page.

### Add to `.csproj`

```xml
<Content Include="Javascript\MyControl.js" />
```

### Add to `CopyWebUI.bat`

```bat
copy "%PROJECT_DIR%Javascript\MyControl.js" "%WEB_APPLICATION_DIR%\Custom\scripts"
```

The `Custom\scripts` directory is already created by the `mkdir` guards at the top of the bat.

---

## CSS Conventions and Wiring

Every standalone OA control ships its own stylesheet. Follow these conventions so all
custom controls share a consistent visual language.

### CSS class naming

All custom classes use the `.cx-` prefix to avoid collisions with OA framework styles.

| Class | Purpose |
|---|---|
| `.cx-{control}-container` | Root wrapper for the entire control |
| `.cx-instructions` | Instruction bar above the form |
| `.cx-form-label` | Bold label cell in a form table |
| `.cx-listbox` | `<asp:ListBox>` element |
| `.cx-listbox-header` | Bold label above a listbox |
| `.cx-btn` | Move / action button (not a toolbar command) |
| `.cx-grid` | Browse or results `<table>` / GridView |
| `.cx-selected-row` | Applied to `<SelectedRowStyle>` in GridView |

### Color palette (from FloatingShelves.css / OAControls.css)

| Token | Value | Use |
|---|---|---|
| Interactive blue | `#0591E5` | Links, button borders, focus rings, icon accents |
| Grid header | `#5396d2` | `<th>` background in browse grids |
| Selected row | `#cce4ff` / `#003366` | Highlighted row bg / text |
| Hover tint | `#e6f3ff` | Hover background for links and rows |
| Border | `#ccc` | Input and listbox borders |

Font family: `'Segoe UI', Tahoma, Geneva, Verdana, sans-serif` (14px base, 13px inside grids/listboxes).
Semibold variant: `"Segoe UI Semibold", 'Segoe UI', sans-serif` for column headers and select links.

### Custom webkit scrollbar (from OAControls.css)

Always add to `.cx-listbox`:

```css
.cx-listbox::-webkit-scrollbar       { width: 8px; }
.cx-listbox::-webkit-scrollbar-track { background: #f1f1f1; border-radius: 4px; }
.cx-listbox::-webkit-scrollbar-thumb { background: #ccc;    border-radius: 4px; }
.cx-listbox::-webkit-scrollbar-thumb:hover { background: #999; }
```

### Wiring the stylesheet

**1. ASCX `<link>` tag** — place in the `<head>` block of the ASCX (see JavaScript File Wiring for the full `<html>/<head>/<body>` structure). Use a relative path — not `ResolveUrl`:

```aspx
<link rel="stylesheet" type="text/css" href="custom/styles/MyControl.css" />
```

**2. Add to `.csproj`** as a `<Content>` item so VS includes it in the project:

```xml
<Content Include="CSS\MyControl.css" />
```

**3. Add to `CopyWebUI.bat`** so the stylesheet deploys alongside the ASCX and DLL:

```bat
copy "%PROJECT_DIR%CSS\MyControl.css" "%WEB_APPLICATION_DIR%\Custom\Styles"
```

The `Custom\Styles` directory is already created by the `mkdir` guards at the top of the bat.
