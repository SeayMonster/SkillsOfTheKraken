---
name: crisp-dev-openaccess-controls
description: >
  Build new OpenAccess (OA) custom controls for the Cantactix/BlueYonder platform in C#.
  Use this skill whenever the user asks to create, extend, or modify an OA control, UserControlBase,
  derived grid, ASCX user control, or any feature involving SubscriptionManager, ICommandManager,
  IPopupControlSubscriber, planogram selection popups, or CommandFactory database access.
  Also use when the user mentions AccountFieldMapping, DataImporter, FloatingShelves,
  GeneralAccountSettings, OADerivedControls, or PlanogramUpdater patterns. Trigger for any
  request that involves writing C# for a BlueYonder/Cantactix customization control, even if
  the user doesn't say "OA control" explicitly.
---

# OpenAccess (OA) Control Development

You are building C# customization controls for the Cantactix/BlueYonder OpenAccess platform.
Follow these patterns precisely — they are extracted directly from production controls
(AccountFieldMapping, DataImporter, FloatingShelves, GeneralAccountSettings, OADerivedControls, PlanogramUpdater).

Read `references/patterns.md` for full code templates. This file covers the most critical decisions.

Read `references/project-structure.md` when scaffolding a new project from scratch — it contains the complete `.csproj` template, `CopyWebUI.bat`, `packages.config`, `Web.config`, and `Libraries` setup. A sample OA project (e.g. `SampleOAProject`) is kept in the solution and source control as the authoritative `Libraries\` source; copy DLLs from its `Libraries\` folder — ask the user for the name of the sample project in their solution if it differs.

---

## First Decision: SaaS or On-Prem Deployment?

Before writing any job-processing logic, confirm which deployment model the project targets:

**SaaS (BlueYonder hosted)** — BY does not allow background services to run in their environment.
- Submit inserts the job into `cx_job` (for tracking), then **immediately calls the process proc** in the same web request.
- No Automator/service exists; processing is synchronous and on-demand.
- Configured via `CXCustomizations.config`: `<add key="DeploymentMode" value="SaaS" />`

**On-Prem** — a Windows service or Automator process polls `cx_job` and processes jobs asynchronously.
- Submit **only inserts** the job into `cx_job`; the service picks it up and calls the process proc.
- Configured via `CXCustomizations.config`: `<add key="DeploymentMode" value="OnPrem" />`

Both paths insert the job first so the record always exists for tracking/auditing. The only difference is whether the process proc is called immediately or deferred to the service.

> **Ask before writing submit logic:**
> "Is this project for a SaaS (BlueYonder-hosted) environment or an on-prem installation?"

See `references/patterns.md` → **Job Queue Pattern** for the full SaaS/on-prem code split.

---

## First Decision: Derived Control or Standalone Control?

Before writing any code, establish which type the user needs:

**Derived Control** — extends an existing OA framework grid class. Use when:
- Adding custom commands/behavior to an existing OA grid (product grid, planogram grid, etc.)
- The user says things like "add a button to the existing grid" or "when the user clicks X in the grid"
- Lives in the `OADerivedControls` project or a `DerivedGrid/` folder

**Standalone Control** — a complete UI workflow with its own ASCX. Use when:
- Building a new screen, wizard, import/export flow, or configuration panel
- The user describes a multi-step workflow, form, or new page
- Inherits from `UserControlBase`

**If the user mentions planogram selection but doesn't specify which type — ask before writing code:**
> "Should this planogram selection be added to an existing derived control, or is this a new standalone control?"

---

## Project Folder Structure

```
MyControl/
  MyControl.csproj
  CopyWebUI.bat             ← post-build copy script
  Libraries/                ← local copies of JDA/Intactix DLLs (copied from SampleOAProject\Libraries)
  Views/
    MyControlUI.ascx
    MyControlUI.ascx.cs
  DerivedGrid/              ← only if extending a grid
    CXMyGrid.cs
  HelperClasses/
    CommandFactory.cs
    ConfigurationHelper.cs
    SessionHelper.cs        ← only if complex session state needed
  Models/
    MyControlModel.cs
    SelectionModel.cs       ← only if planogram/popup selection used
  Enums/
    eMyEnum.cs              ← only if enums needed
```

---

## Libraries Folder

Every OA project carries its own local copy of the JDA/Intactix DLLs.

**Setup steps:**
1. Copy `SampleOAProject\Libraries\` into the new project root as `Libraries\`
2. Set all JDA HintPaths in the `.csproj` to `Libraries\<dll name>` (not a relative path to SampleOAProject)
3. Register each DLL as a `<Content>` item in the `.csproj` so VS shows it in Solution Explorer

**Required DLLs (all 15):**
```
JDA.Intactix.Common.dll
JDA.Intactix.Configuration.dll
JDA.Intactix.DataAccess.dll
JDA.Intactix.IKB.Common.dll
JDA.Intactix.IKB.DataAccess.dll
JDA.Intactix.IKB.Support.dll
JDA.Intactix.IKB.Web.Common.dll
JDA.Intactix.IKB.Web.dll
JDA.Intactix.IKB.Web.Framework.dll
JDA.Intactix.IKB.Web.UI.dll
JDA.Intactix.IKB.Web.UI.WebControls.dll
JDA.Intactix.Web.Common.dll
JDA.Intactix.Web.Framework.dll
JDA.Intactix.Web.UI.WebControls.dll
Newtonsoft.Json.dll
```

---

## Post-Build Copy (CopyWebUI.bat)

Every OA project must have a `CopyWebUI.bat` that deploys the compiled output to the OA install directory, wired via `<PostBuildEvent>` in the `.csproj`.

**CopyWebUI.bat pattern:**
```bat
exit 0
SET PROJECT_DIR=%~1%

SET WEB_APPLICATION_DIR=C:\Program Files (x86)\JDA\Intactix\Intactix Knowledge Base\Open Access

if not exist "%WEB_APPLICATION_DIR%\Custom"         mkdir "%WEB_APPLICATION_DIR%\Custom"
if not exist "%WEB_APPLICATION_DIR%\Custom\Config"  mkdir "%WEB_APPLICATION_DIR%\Custom\Config"
if not exist "%WEB_APPLICATION_DIR%\Custom\Styles"  mkdir "%WEB_APPLICATION_DIR%\Custom\Styles"
if not exist "%WEB_APPLICATION_DIR%\Custom\scripts" mkdir "%WEB_APPLICATION_DIR%\Custom\scripts"

copy "%PROJECT_DIR%Views\*.ascx"                        "%WEB_APPLICATION_DIR%\Custom"
copy "%PROJECT_DIR%bin\MyControl.dll"                   "%WEB_APPLICATION_DIR%\bin"
copy "%PROJECT_DIR%CSS\MyControl.css"                   "%WEB_APPLICATION_DIR%\Custom\Styles"
copy "%PROJECT_DIR%Javascript\MyControl.js"             "%WEB_APPLICATION_DIR%\Custom\scripts"
copy "%PROJECT_DIR%Config\CrispCustomizations.config"   "%WEB_APPLICATION_DIR%\Custom\Config"
```

`exit 0` on line 1 is a safety disable — the script exits immediately on machines without OA installed. Comment it out on dev machines where you want the copy to run.

**Wire into `.csproj`** (visible in VS → Project Properties → Build Events):
```xml
<PropertyGroup>
  <PostBuildEvent>"$(ProjectDir)CopyWebUI.bat" "$(ProjectDir)"</PostBuildEvent>
</PropertyGroup>
```

Also add the bat to the project as a `<None>` item:
```xml
<None Include="CopyWebUI.bat" />
```

---

## Required Using Statements

### Derived Grid Control
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

### Standalone Control (UserControlBase)
```csharp
using JDA.Intactix.IKB.Web.Framework;
using JDA.Intactix.IKB.Web.UI;
using JDA.Intactix.Web.Framework;

using Newtonsoft.Json;

using System;
using System.Collections.Generic;
using System.Data;
using System.Web.UI.WebControls;
```

### CommandFactory
```csharp
using Dapper;
using JDA.Intactix.IKB.DataAccess;
using Serilog.Core;
using System;
using System.Data;
using System.Data.SqlClient;
```

### ConfigurationHelper
```csharp
using Serilog;
using Serilog.Core;
using Serilog.Sinks.RollingFileAlternate;
using System;
using System.Configuration;
using System.IO;
using System.Web;
```

---

## Base Classes and Interfaces

| Scenario | Base Class | Interfaces |
|---|---|---|
| New UI screen / workflow | `UserControlBase` | `ICommandManager`, optionally `IPopupControlSubscriber` |
| Extend OA grid with custom commands | `AdvancedTableGrid` | `ICommandManager` |
| Extend dictionary-style grid | `AdvancedDictionaryGrid` | `ICommandManager`, optionally `IMessageCommand` |
| Simple reorderable grid | `TableGrid` | — |

---

## SubscriptionManager (Inter-Control Communication)

Controls communicate via a publish/subscribe system. Wire this up in the control's constructor.

```csharp
// Subscribe: this control LISTENS for these values
SubscriptionManager.AddKeyToSubscribe(CommonConstants.OA_Command_MappingKey);
SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBKey);

// Publish: this control EMITS these values
SubscriptionManager.AddKeyToPublish("_updated");

// Emit a value (other subscribed controls react via OnMessageReceived)
SubscriptionManager.Publish(this, CommonConstants.OA_Command_MappingKey, value);

// Read a value from the page store
var val = SubscriptionManager.GetPageStoreData(this, CommonConstants.OA_Command_MappingKey);

// React to a published value
protected override void OnMessageReceived(object sender, DataStoreChangedEventArgs e)
{
    if (e.Key.Equals(SubscriptionManager.SubscribedKey(CommonConstants.OA_Command_MappingKey),
                     StringComparison.OrdinalIgnoreCase))
    {
        // respond to the change
        base.Refresh();
    }
}
```

**Key published keys used across projects:**
- `PublishedKey.DBKey` — selected row's database key
- `PublishedKey.JsDBKeyList` — multi-select keys, `#`-delimited
- `PublishedKey.HierarchyDBKeySelectedNodeList` — hierarchy node selections
- `PublishedKey.DBStatusList` — planogram status selections
- `CommonConstants.SESSION_UIModel` — JSON-serialized UI model

---

## Planogram / Item Selection Popup

Two distinct patterns depending on selection type. Choose before writing any code.

### Multi-select via built-in OA Explorer
Use when the user must pick one or more planograms from the standard OA hierarchy/explorer UI.
- Open with `PageKey = _commandFactory.GetPageKey("CKB Multi-select Planogram Explorer")`
- Constructor: subscribe to `PublishedKey.HierarchyDBKeyList`, `PublishedKey.JsDBKeyList`, `PublishedKey.DBStatusList`
- Results arrive in `Receive()` via `PublishedKey.JsDBKeyList` (keys delimited by `#`)
- See `references/patterns.md` → **Planogram Selection Pattern (Multi-select)**

### Single-select via built-in OA Explorer
Use when the user must pick exactly one planogram from the standard OA explorer UI (no multi-select).
- Open with `PageKey = _commandFactory.GetPageKey("CKB Planogram Explorer")`
- Constructor: subscribe to `PublishedKey.DBKey` only (NOT `JsDBKeyList` — the single-select explorer publishes `DBKey` as a plain integer)
- Result arrives in `Receive()` via `PublishedKey.DBKey` — parse `e.ReturnValue` directly as `int`, no `#`-split needed
- Also `AddKeyToPublish(CommonConstants.SESSION_SelectedPogKey)` in constructor for the JSON snapshot refresh pattern
- See `references/patterns.md` → **Planogram Selection Pattern (Single-select)**

### Single-select via custom ASCX popup
Use when the built-in explorer UI is not appropriate and you need a fully custom list/grid popup.
- Build a popup ASCX that implements `IPopupCommandManager`
- Popup constructor: `SubscriptionManager.AddKeyToPublish(CommonConstants.SESSION_SelectedKey)`
- Popup `ExecuteCommandOnPopupOK()`: `SubscriptionManager.Publish(this, key, dbKey)`
- Open with `ControlTemplate { ControlType="ascx", Name="MySelectUI", Path="~/Custom" }`
- Parent constructor: `SubscriptionManager.AddKeyToSubscribe(CommonConstants.SESSION_SelectedKey)`
- Parent `Receive()`: guard on `e.Key != key`, read `e.ReturnValue`
- See `references/patterns.md` → **Custom Single-Select Popup (IPopupCommandManager)**

**Opening a custom ASCX popup from a derived grid (data-passing variant):**
- Pass input data via `popup.AddParameter("ObjectKeys", objectKeys)` — stored in `HttpContext.Current.Items`
- The popup reads it back with `Context.Items["ObjectKeys"]?.ToString()` — NOT via `SubscriptionManager`
- The grid constructor must NOT `AddKeyToPublish("_updated")` — only the popup view owns that signal
- See `references/patterns.md` → **Opening a Custom ASCX Popup**

---

## Database Access (CommandFactory + Dapper)

All database work goes through a `CommandFactory` class using Dapper. Never use raw ADO.NET
`DataAdapter` or `SqlCommand` directly — always go through `DynamicParameters` and stored procedures.

Stored procedure naming convention: `{_customSchema}.cx_[noun]_[verb]`
Examples: `ckbcustom.cx_accnt_fieldmap_get`, `ckbcustom.cx_job_ins`

Every stored procedure file must end with `GO` then `GRANT EXECUTE ON {schema}.{proc} TO public;`
Every table script must end with `GRANT SELECT, UPDATE, INSERT, DELETE ON {schema}.{table} TO public;`

**Job queue pattern:** When a UI action triggers a long-running operation (copy, version, promote), always insert a job row into `ckbcustom.cx_job` with the full model serialized as JSON. This provides tracking regardless of deployment mode.

- **On-prem**: insert only — an Automator/service polls `cx_job` and calls the process proc.
- **SaaS**: insert, then immediately call the process proc in the same request (no background service available in BY-hosted environments).

Read `DeploymentMode` from config to branch the submit path. Never hardcode the mode.

```csharp
_commandFactory.InsertJob(_uiModel, Helper.CurrentUser, "POG Split");
if (_commandFactory.IsSaaS())
    _commandFactory.ProcessJob(_uiModel);
```

See `references/patterns.md` → **Job Queue Pattern** for the full SaaS/on-prem template.

See `references/patterns.md` → **CommandFactory Pattern** for the full template.

---

## Configuration

Always read `CustomSchema` from `CXCustomizations.config` via `ConfigurationHelper`.
Never hardcode schema names like `"ckbcustom"` directly in code.

```csharp
_customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");
```

---

## Logging (Serilog)

Every class gets a static `Logger`. Every significant method wraps its work with Start/Finish logs.

```csharp
private static readonly Logger _logger = ConfigurationHelper.CreateLogger("MyFeatureName");

internal void DoSomething()
{
    _logger.Information("Starting DoSomething()");
    try { /* work */ }
    catch (Exception ex) { _logger.Error(ex, "DoSomething Exception"); }
    _logger.Information("Finished DoSomething()");
}
```

---

## ICommandManager — Toolbar Buttons

```csharp
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
                // perform the save
                SubscriptionManager.Publish(this, "_updated", 1);
                OnDisplayMessage(new MessageEventArgs()
                {
                    Message = "Saved successfully",
                    MessageLocation = MessageLocations.BottomLeft,
                    EventType = MessageEventTypes.Success
                });
                break;
        }
    }
    catch (Exception ex) { _logger.Error(ex, "DoCommand Exception"); }
}
```

---

## User Feedback Messages

Always use `OnDisplayMessage()` — never `Response.Write`, `Console.Write`, or labels directly.

```csharp
// Success
OnDisplayMessage(new MessageEventArgs()
{
    Message = "Operation completed.",
    EventType = MessageEventTypes.Success,
    MessageLocation = MessageLocations.BottomLeft
});

// Error
OnDisplayMessage(new MessageEventArgs()
{
    Message = "Validation failed: field is required.",
    EventType = MessageEventTypes.Error,
    MessageLocation = MessageLocations.BottomLeft
});
```

---

## Excel Import Validation Sequence

When processing Excel uploads, always run these checks in order before processing data:

1. `IsHeadersValid()` — required columns exist
2. `IsHeadersReadOnly()` — no read-only columns included
3. `IsBadColumns()` — no unrecognized columns
4. `IsDuplicateColumns()` — no duplicate column names
5. `IsNotNumeric()` — numeric fields contain valid numbers
6. `CheckFieldLengths()` — field values within length limits

---

## Non-Negotiable Rules

1. **Logging**: Every method of significance gets Start/Finish `_logger.Information()` calls
2. **Schema**: Always read from config — never hardcode `"ckbcustom"` or any schema name
3. **Database**: Dapper + `DynamicParameters` + stored procs only; call `ConnectionCleanup()` after every operation
4. **Session state**: Complex state lives in a JSON-serialized model published via `SubscriptionManager`; load in `OnInit`, bind in `OnPreRender`, publish after every mutation
5. **Popup results**: Implement `IPopupControlSubscriber.Receive()` when any popup selection is used; choose multi-select (built-in explorer) vs single-select (`IPopupCommandManager`) before writing code
6. **Messages**: `OnDisplayMessage()` only — no raw writes to response or page controls
7. **Models**: Plain C# classes in `Models/` folder; serialize with `JsonConvert.SerializeObject()`
8. **List transfers**: Use JS `<button type="button">` + jQuery `.detach()` for client-side list moves; track destination state in a `<asp:HiddenField>`; call `SyncModelFromHiddenField()` + `PublishModel()` at the top of `Submit()` before validating
9. **CSS**: Every standalone control gets a `CSS\MyControl.css` using `.cx-` prefixed classes and the shared color palette (`#0591E5` interactive blue, `#5396d2` grid headers). Wire it with `ResolveUrl` in the ASCX `<link>` tag, a `<Content>` entry in the csproj, and a `copy` line in `CopyWebUI.bat`. See `references/patterns.md` → **CSS Conventions and Wiring**
9b. **JavaScript**: Every standalone control that needs client-side behavior gets a `Javascript\MyControl.js` file — never inline `<script>` blocks in the ASCX. Add `ClientIDMode="Static"` to any control the JS must reference by ID. For client-only `asp:Button` controls, also add `UseSubmitBehavior="false" OnClientClick="return false;"`. Use `Sys.Application.add_load` (not `$(document).ready`) — the OA framework loads jQuery after script tags execute so the jQuery IIFE fails silently. To inject diagnostic or startup script from code-behind use `ScriptManager.RegisterClientScriptBlock` — `Page.ClientScript` is silently ignored when ScriptManager is present. See `references/patterns.md` → **JavaScript File Wiring**
10. **Group boxes**: Use `<fieldset>` + `<legend>` + `<asp:Panel CssClass="hostPanel">` to visually group sections. Legend title uses an `<asp:Label>` with `Font-Names="Segoe UI Semibold"`. All form tables inside fieldsets use `<asp:Table>/<asp:TableRow>/<asp:TableCell>`. See `references/patterns.md` → **Fieldset Group Box Pattern**
11. **Refresh snapshot**: When a planogram (or item) is selected, publish a JSON snapshot of the full model to `SESSION_SelectedPogKey`. In `OnInit`, clear on `!IsPostBack`; restore from snapshot on postback if `SESSION_UIModel` is empty. See `references/patterns.md` → **JSON Snapshot Refresh Pattern**
12. **Clarify ambiguity**: If planogram selection type (derived vs. standalone) is unclear, ask before writing code
