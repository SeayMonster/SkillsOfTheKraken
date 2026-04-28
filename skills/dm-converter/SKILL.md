---
name: dm-converter
description: >
  Analyze a Data Manager .fsf form file and convert it to an equivalent OpenAccess (OA)
  UserControlBase control. Use this skill whenever the user provides an .fsf file or
  describes a Data Manager form and asks to recreate, migrate, or build the equivalent
  OA control. Also use when the user mentions Data Manager, DM forms, ProfusionHierarchyCtrl1,
  VBScript event handlers, .fsf files, or legacy Profusion forms.
---

# FSF → OA Control Conversion

You are converting a legacy Data Manager (DM) form file (`.fsf`) into an equivalent
OpenAccess (OA) UserControlBase control in C#.

Read `references/control-map.md` for the complete mapping tables between DM controls,
VBScript patterns, and their OA/C# equivalents.

---

## Step 1 — Read the .fsf File

`.fsf` files are **OLE Compound Document** binary containers. They embed control metadata
and VBScript event-handler code as wide-character (UTF-16LE) strings. The companion
`.fsf.dat` is a compiled binary — do **not** attempt to read it.

**How to extract useful content from the .fsf:**
Use the `Read` tool on the `.fsf` file. Despite being binary, the embedded strings are
readable because they appear as wide-character text interspersed with binary. Look for:

1. **Control type identifiers** — appear near control names:
   - `CObjCheckbox` — checkbox
   - `CObjEdit` — single-line or multi-line text input
   - `CObjActiveX` — embedded ActiveX control (look for ProgID nearby, e.g. `ProfusionHierarchyCtrl.ProfusionHierarchyCtrl.1`)
   - `CObjTextBlock` — read-only label
   - `CScriptManager` — holds the VBScript code-behind (not a UI control)
   - `CShellObject` — shell/command object
   - `CObjCombo` — combo box / dropdown

2. **Control names** — appear as readable strings near their type identifier.
   Example: `ProfusionHierarchyCtrl1`, `chx_ExportByNode`, `txtFilePath`, `cmbSheetName`

3. **VBScript code** — large block of readable text containing `Sub` and `Function` definitions,
   `Application.` calls, `ADODB.Command`, etc.

4. **Form title** — appears near the top as a readable string.

When reading the .fsf, scan broadly for these patterns. The binary structure varies by
form; there is no fixed offset. Focus on extracting:
- All control names and their types
- The complete VBScript code block
- The form title

---

## Step 2 — Inventory the Form

Before writing any OA code, produce an inventory table:

| DM Control Name | DM Type | Purpose (inferred from name + usage in VBScript) | OA Equivalent |
|---|---|---|---|
| ProfusionHierarchyCtrl1 | CObjActiveX | Hierarchy node selector | SubscriptionManager `PublishedKey.HierarchyDBKeySelectedNodeList` |
| chx_ExportByNode | CObjCheckbox | Mode selection | `<asp:CheckBox>` in ASCX |
| txtFilePath | CObjEdit | File path input | `<asp:TextBox>` in ASCX |
| cmbSheetName | CObjCombo | Excel sheet picker | `<asp:DropDownList>` in ASCX |
| cmd_DoAction | CObjEdit (button) | Submit trigger | `ICommandManager.GetCommands()` toolbar button |

See `references/control-map.md` for the full mapping table.

---

## Step 3 — Analyze the VBScript Business Logic

Read the VBScript code-behind and categorize each `Sub`/`Function` into one of:

| Category | VBScript Pattern | OA Equivalent |
|---|---|---|
| **Initialization** | `Sub Form_Load()` | `LoadUI()` called from `OnInit` |
| **Validation** | Guard clauses at top of action Sub | Private `Validate()` method |
| **Data read** | `Application.GetRecordset(strSQL)` | `CommandFactory` query with Dapper |
| **SP call** | `ADODB.Command` with `.Parameters.Append` | `CommandFactory` method with `DynamicParameters` |
| **File I/O** | `Scripting.FileSystemObject` | `System.IO.File` / `System.IO.Path` |
| **Excel COM** | `CreateObject("Excel.Application")` | `ClosedXML` or `EPPlus` NuGet package |
| **BCP bulk load** | `Shell "bcp ..."` | Keep as `Process.Start("bcp", ...)` wrapped in CommandFactory |
| **Status message** | `Application.ShowStatusMsg` | `OnDisplayMessage(MessageEventTypes.Success)` |
| **Wait cursor** | `Application.ShowWaitCursor` | No equivalent needed (OA handles loading state) |
| **Navigation** | `Application.NavigateToFrameworkMemberEx` | Not applicable in OA controls |
| **Message box** | `Application.MessageBox` | `OnDisplayMessage(MessageEventTypes.Error)` |
| **Hierarchy selection read** | `ProfusionHierarchyCtrl1.Object.SelectedLeafKeys` | `SubscriptionManager.GetPageStoreData(this, PublishedKey.HierarchyDBKeySelectedNodeList)` |

---

## Step 4 — Determine the OA Control Type

Use the `oa-controls` skill to determine **Derived Control vs. Standalone Control**.

**Data Manager forms almost always become Standalone Controls** (`UserControlBase`) because:
- They have their own full UI layout
- They are independent workflows (import, export, bulk action)
- They are not extending an existing OA grid

Only use a Derived Control if the form was acting as a detail panel triggered from a grid row.

---

## Step 5 — Map Hierarchy Selection

DM forms that use `ProfusionHierarchyCtrl1` get their selections via direct ActiveX property access:
```vbscript
strKeys = ProfusionHierarchyCtrl1.Object.SelectedLeafKeys
strKeyText = ProfusionHierarchyCtrl1.Object.SelectedLeafKeyText
```

In OA, the hierarchy control is a separate registered control on the OA page. The selected
keys arrive via `SubscriptionManager`:

```csharp
// In constructor
SubscriptionManager.AddKeyToSubscribe(PublishedKey.HierarchyDBKeySelectedNodeList);

// In OnMessageReceived
protected override void OnMessageReceived(object sender, DataStoreChangedEventArgs e)
{
    if (e.Key.Equals(SubscriptionManager.SubscribedKey(PublishedKey.HierarchyDBKeySelectedNodeList),
                     StringComparison.OrdinalIgnoreCase))
    {
        var keys = SubscriptionManager.GetPageStoreData(this, PublishedKey.HierarchyDBKeySelectedNodeList)?.ToString();
        _uiModel.NodeKeys = keys;
        base.Refresh();
    }
}
```

If the DM form also read `SelectedStatus` or `GetSelectedDataKeys`, use `PublishedKey.DBStatusList`
or `PublishedKey.JsDBKeyList` respectively.

---

## Step 6 — Map Data Access

### Application.GetRecordset → CommandFactory query

```vbscript
' DM VBScript
Dim rs
Set rs = Application.GetRecordset("SELECT col1, col2 FROM ckbcustom.cx_mytable WHERE id = " & someId)
While Not rs.EOF
    DoSomething rs("col1").Value
    rs.MoveNext
Wend
```

```csharp
// OA CommandFactory (Dapper)
internal IEnumerable<MyModel> GetMyData(int id)
{
    _logger.Information("Starting GetMyData()");
    try
    {
        using (var conn = GetDbConnection())
        {
            var p = new DynamicParameters();
            p.Add("id", id, dbType: DbType.Int32);
            var result = conn.Query<MyModel>($"{_customSchema}.cx_mydata_get", p,
                commandType: CommandType.StoredProcedure);
            ConnectionCleanup(conn);
            return result;
        }
    }
    catch (Exception ex) { _logger.Error(ex, "GetMyData Exception"); }
    _logger.Information("Finished GetMyData()");
    return Enumerable.Empty<MyModel>();
}
```

### ADODB.Command SP call → CommandFactory DynamicParameters

```vbscript
' DM VBScript
Dim cmd
Set cmd = CreateObject("ADODB.Command")
cmd.ActiveConnection = Application.ProfusionSupport.ADOConnection
cmd.CommandType = 4  ' adCmdStoredProc
cmd.CommandText = "ckbcustom.cx_automator_action_list_ins"
cmd.Parameters.Append cmd.CreateParameter("@username", 200, 1, 100, strUser)
cmd.Parameters.Append cmd.CreateParameter("@filepath", 200, 1, 255, strFile)
cmd.Execute
```

```csharp
// OA CommandFactory
internal void InsertActionList(string username, string filepath)
{
    _logger.Information("Starting InsertActionList()");
    try
    {
        using (var conn = GetDbConnection())
        {
            var p = new DynamicParameters();
            p.Add("username", username, dbType: DbType.String, size: 100);
            p.Add("filepath", filepath, dbType: DbType.String, size: 255);
            conn.Execute($"{_customSchema}.cx_automator_action_list_ins", p,
                commandType: CommandType.StoredProcedure);
            ConnectionCleanup(conn);
        }
    }
    catch (Exception ex) { _logger.Error(ex, "InsertActionList Exception"); }
    _logger.Information("Finished InsertActionList()");
}
```

---

## Step 7 — Map File and Excel Operations

### BCP bulk load

BCP calls remain as-is but move into a dedicated `CommandFactory` method using `Process.Start`:

```csharp
internal void BulkLoadFile(string filepath, string tableName)
{
    _logger.Information($"Starting BulkLoadFile() table={tableName}");
    try
    {
        var server   = ConfigurationHelper.GetConfigSetting("ServerName");
        var database = ConfigurationHelper.GetConfigSetting("DatabaseName");
        var args = $"{tableName} in \"{filepath}\" -S {server} -d {database} -T -c -t,";
        var psi = new ProcessStartInfo("bcp", args) { UseShellExecute = false };
        using var proc = Process.Start(psi);
        proc?.WaitForExit();
    }
    catch (Exception ex) { _logger.Error(ex, "BulkLoadFile Exception"); }
    _logger.Information("Finished BulkLoadFile()");
}
```

### Excel COM → ClosedXML

```vbscript
' DM — convert xlsx to csv
Set oXL = CreateObject("Excel.Application")
Set oWB = oXL.Workbooks.Open(strFilePath)
Set oWS = oWB.Worksheets(cmbSheetName.Text)
oWB.SaveAs strCsvPath, 6  ' xlCSV
oXL.Quit
```

```csharp
// OA — ClosedXML
using var wb = new XLWorkbook(filePath);
var ws = wb.Worksheet(sheetName);
// Write to CSV manually or use a library helper
```

---

## Step 8 — Scaffold the OA Control

Follow the `oa-controls` skill for project structure, using the inventory from Step 2 to
determine which files are needed. Minimum set for a typical DM form migration:

```
MyControl/
  MyControl.csproj
  CopyWebUI.bat
  Libraries/                 ← copy from SampleOAProject
  Views/
    MyControlUI.ascx         ← HTML for all CObjEdit, CObjCheckbox, CObjCombo controls
    MyControlUI.ascx.cs      ← UserControlBase, ICommandManager, IPopupControlSubscriber (if needed)
  HelperClasses/
    CommandFactory.cs        ← one method per VBScript data operation
    ConfigurationHelper.cs
  Models/
    MyControlModel.cs        ← one property per form input + result state
```

**ASCX layout guidance from DM control inventory:**
- `CObjCheckbox` → `<asp:CheckBox runat="server" ID="chkXxx" />`
- `CObjEdit` (single line) → `<asp:TextBox runat="server" ID="txtXxx" />`
- `CObjEdit` (multi-line) → `<asp:TextBox runat="server" ID="txtXxx" TextMode="MultiLine" />`
- `CObjCombo` → `<asp:DropDownList runat="server" ID="ddlXxx" />`
- `CObjTextBlock` → `<asp:Label runat="server" ID="lblXxx" />`
- `CObjActiveX` (hierarchy) → No ASCX control needed; subscribe to `PublishedKey.HierarchyDBKeySelectedNodeList`
- Submit button (was `cmd_Xxx` or the primary action) → `ICommandManager.GetCommands()` toolbar button

---

## Step 9 — Non-Negotiable Rules

1. Follow all rules from the `oa-controls` skill (logging, schema from config, Dapper, messages).
2. Never call BCP synchronously if it takes more than a few seconds — use the job queue pattern.
3. DM forms often use hardcoded server/database names from `Application.ProfusionSupport.HostName`
   and `.DatabaseName` — replace these with `ConfigurationHelper.GetConfigSetting("ServerName")`
   and `ConfigurationHelper.GetConfigSetting("DatabaseName")`.
4. DM checkboxes used for mode selection (e.g. "export by node vs. by planogram") become
   radio buttons or a `<asp:RadioButtonList>` in the ASCX — more idiomatic for mutual exclusion.
5. Hierarchy selections arrive asynchronously via `SubscriptionManager` — do not read them
   in `Page_Load`. Store them in `_uiModel` when `OnMessageReceived` fires, then read from
   `_uiModel` at submit time.
6. Always ask: does this form trigger a long-running operation? If yes, use the job queue
   pattern (`InsertJob`) instead of executing synchronously in `DoCommand`.
