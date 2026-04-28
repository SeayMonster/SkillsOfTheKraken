# DM Control → OA Control Mapping

## UI Controls

| DM Type | DM Example Name | OA / ASCX Equivalent | Notes |
|---|---|---|---|
| `CObjCheckbox` | `chx_ExportByNode` | `<asp:CheckBox runat="server" ID="chkExportByNode" />` | Mutual-exclusion pairs → `<asp:RadioButtonList>` |
| `CObjEdit` (1-line) | `txtFilePath` | `<asp:TextBox runat="server" ID="txtFilePath" />` | |
| `CObjEdit` (multi-line) | `txtSQL` | `<asp:TextBox ... TextMode="MultiLine" Rows="5" />` | Infer from height in .fsf or from VBScript usage |
| `CObjCombo` | `cmbSheetName` | `<asp:DropDownList runat="server" ID="ddlSheetName" />` | Populate in `LoadUI()` |
| `CObjTextBlock` | `lblStatus` | `<asp:Label runat="server" ID="lblStatus" />` | Read-only display text |
| `CObjActiveX` (hierarchy) | `ProfusionHierarchyCtrl1` | No ASCX control — subscribe `PublishedKey.HierarchyDBKeySelectedNodeList` | Keys arrive via `OnMessageReceived` |
| `CObjActiveX` (other) | varies | Evaluate ProgID; most have a web equivalent | Document each one |
| Action button (`cmd_Xxx`) | `cmd_CheckData`, `cmd_Submit` | `ICommandManager.GetCommands()` toolbar button | Primary action → `CommandLocations.TopRight` |
| `CScriptManager` | — | No OA equivalent — contains VBScript code only | Extract and translate VBScript |
| `CShellObject` | — | `Process.Start()` in CommandFactory | Shell commands / BCP calls |

---

## VBScript API → C# / OA API

| VBScript | C# / OA Equivalent |
|---|---|
| `Application.GetRecordset("SELECT ...")` | `conn.Query<T>(sql)` via Dapper in CommandFactory |
| `Application.ProfusionSupport.ADOConnection` | `GetDbConnection()` in CommandFactory |
| `Application.ProfusionSupport.HostName` | `ConfigurationHelper.GetConfigSetting("ServerName")` |
| `Application.ProfusionSupport.DatabaseName` | `ConfigurationHelper.GetConfigSetting("DatabaseName")` |
| `Application.ShowStatusMsg("...")` | `OnDisplayMessage(new MessageEventArgs { EventType = MessageEventTypes.Success, ... })` |
| `Application.ShowWaitCursor True/False` | Not needed — OA handles loading state |
| `Application.MessageBox "..."` | `OnDisplayMessage(new MessageEventArgs { EventType = MessageEventTypes.Error, ... })` |
| `Application.NavigateToFrameworkMemberEx` | Not applicable in OA controls |
| `ADODB.Command` + `.Parameters.Append` | `DynamicParameters` + `conn.Execute(spName, p, CommandType.StoredProcedure)` |
| `ADODB.Recordset` field access `rs("col")` | Dapper maps to strongly-typed C# model properties |
| `CreateObject("Scripting.FileSystemObject")` | `System.IO.File`, `System.IO.Path`, `System.IO.Directory` |
| `CreateObject("Excel.Application")` | `ClosedXML` (`XLWorkbook`) or `EPPlus` |
| `Shell "bcp ..."` | `Process.Start("bcp", args)` in CommandFactory, or job queue for long-running |
| `ProfusionHierarchyCtrl1.Object.SelectedLeafKeys` | `SubscriptionManager.GetPageStoreData(this, PublishedKey.HierarchyDBKeySelectedNodeList)` |
| `ProfusionHierarchyCtrl1.Object.SelectedLeafKeyText` | Read from page store; OA key text not directly available — query DB if needed |
| `ProfusionHierarchyCtrl1.Object.GetSelectedDataKeysCount` | `.Split('#').Length` on `JsDBKeyList` value |
| `ProfusionHierarchyCtrl1.Object.GetSelectedDataKeys(i)` | `.Split('#')[i]` on `JsDBKeyList` value |
| `ProfusionHierarchyCtrl1.Object.SelectedStatus` | `SubscriptionManager.GetPageStoreData(this, PublishedKey.DBStatusList)` |

---

## VBScript Sub/Function → OA Method

| VBScript Event/Sub | OA Location | Notes |
|---|---|---|
| `Sub Form_Load()` | `LoadUI()` called from `OnInit` or `OnPreRender` | Populate dropdowns, set defaults |
| Primary action Sub (e.g. `Sub cmd_Submit_Click`) | `DoCommand` `case "Submit":` block | Called by ICommandManager |
| Validation logic at top of action Sub | Private `Validate()` returning `bool` | Call at start of DoCommand case |
| Helper Subs called from multiple places | Private methods on the `.ascx.cs` or CommandFactory | Data ops → CommandFactory; UI ops → code-behind |

---

## ProfusionHierarchyCtrl1 Full API Reference

These are the VBScript properties/methods and their OA equivalents:

```vbscript
' -- Read selected node keys (comma or # delimited)
strKeys = ProfusionHierarchyCtrl1.Object.SelectedLeafKeys
```
→ `SubscriptionManager.GetPageStoreData(this, PublishedKey.HierarchyDBKeySelectedNodeList)?.ToString()`
  Value is `#`-delimited when multiple nodes selected.

```vbscript
' -- Read display text for selected nodes
strText = ProfusionHierarchyCtrl1.Object.SelectedLeafKeyText
```
→ No direct OA equivalent. Query the DB using the keys if the text is needed.

```vbscript
' -- Count selected nodes
intCount = ProfusionHierarchyCtrl1.Object.GetSelectedDataKeysCount
```
→ `keys?.Split('#').Length ?? 0`

```vbscript
' -- Get key at index
strKey = ProfusionHierarchyCtrl1.Object.GetSelectedDataKeys(i)
```
→ `keys?.Split('#')[i]`

```vbscript
' -- Read planogram status selections
strStatus = ProfusionHierarchyCtrl1.Object.SelectedStatus
```
→ `SubscriptionManager.GetPageStoreData(this, PublishedKey.DBStatusList)?.ToString()`

---

## Long-Running Operations

If the DM VBScript Sub executes BCP, multi-step SP chains, or COM automation that takes
more than ~2 seconds, convert to the **job queue pattern**:

1. Collect all inputs into a model class
2. Call `_commandFactory.InsertJob(_uiModel, Helper.CurrentUser, "JobTypeName")`
3. Display a "Job submitted" success message
4. A separate Automator process reads `ckbcustom.cx_job` and executes the actual work

See `oa-controls` skill → `references/patterns.md` → **Job Queue Pattern** for full details.
