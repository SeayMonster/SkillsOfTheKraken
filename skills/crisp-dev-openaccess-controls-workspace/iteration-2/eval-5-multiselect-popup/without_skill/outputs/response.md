# Adding a Multi-Select Planogram Picker to a Standalone OA Control

The platform provides two distinct planogram explorer page names:

- `"CKB Planogram Explorer"` — single-select
- `"CKB Multi-select Planogram Explorer"` — multi-select

The flow is:
1. Your control implements `IPopupControlSubscriber`
2. A `LinkButton` click calls `OnDisplayPopupPage(...)` with the page key resolved at runtime via `_commandFactory.GetPageKey(...)`
3. The platform invokes `Receive(PopupControlEventArgs)` on your control when the user confirms the popup
4. The return arrives under `PublishedKey.JsDBKeyList` as a `#`-delimited string of integer DBKeys

---

## Step 1 — The .ascx markup

```aspx
<%@ Control Language="C#" AutoEventWireup="true"
    CodeBehind="MyControl.ascx.cs"
    Inherits="MyNamespace.Views.MyControl" %>

<div class="cx-my-control">
    <div class="cx-selection-row">
        <asp:LinkButton ID="lnkSelectPlanograms" runat="server"
            CommandName="ObjectExplorerSpace"
            OnClick="PlanogramPicker_Click"
            CssClass="link-button-icon-label">
            <asp:Label ID="lblSelectPlanograms" runat="server"
                Text="Select Planogram(s)" />
        </asp:LinkButton>
    </div>
    <div class="cx-selection-summary">
        <asp:Label ID="lblPogCount" runat="server" Text="No planograms selected." />
    </div>
</div>
```

---

## Step 2 — CommandFactory: GetPageKey

```csharp
internal string GetPageKey(string pageName)
{
    _logger.Information("Starting GetPageKey()");
    var retVal = string.Empty;
    try
    {
        using (var conn = GetDbConnection())
        {
            var parameters = new DynamicParameters();
            parameters.Add("PageName", pageName, dbType: DbType.String, size: 200);

            retVal = conn.ExecuteScalar(
                $"{_customSchema}.cx_page_key_get",
                parameters,
                commandType: CommandType.StoredProcedure)?.ToString();

            ConnectionCleanup(conn);
        }
    }
    catch (Exception ex) { _logger.Error(ex, "GetPageKey Exception"); }
    _logger.Information("Finished GetPageKey()");
    return retVal;
}
```

---

## Step 3 — Code-behind

```csharp
public partial class MyControl : UserControlBase, ICommandManager, IPopupControlSubscriber
{
    private static readonly Logger _logger = ConfigurationHelper.CreateLogger("MyControl");
    private CommandFactory _commandFactory;
    private MyControlModel _uiModel;
    private IKBDbSupport   _dbSupport = new IKBDbSupport(Helper.CurrentUser);

    protected override void OnInit(EventArgs e)
    {
        base.OnInit(e);
        SubscriptionManager.AddKeyToPublish(CommonConstants.SESSION_UIModel);
    }

    protected override void OnLoad(EventArgs e)
    {
        _logger.Information("Starting OnLoad()");
        base.OnLoad(e);

        var customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");
        _commandFactory  = new CommandFactory(_dbSupport, customSchema, _logger);

        if (!IsPostBack)
        {
            _uiModel = new MyControlModel();
            UpdateSelectionLabel();
        }

        _logger.Information("Finished OnLoad()");
    }

    protected void PlanogramPicker_Click(object sender, EventArgs e)
    {
        switch (((LinkButton)sender).CommandName)
        {
            case "ObjectExplorerSpace":
                var pageKey = _commandFactory.GetPageKey("CKB Multi-select Planogram Explorer");
                var popup = new PopupPageEventArgs
                {
                    PageKey          = pageKey,
                    Title            = "Select Planogram(s)",
                    AutoHeight       = true,
                    HideControlTitle = true,
                    HidePageTitle    = true,
                    Buttons          = PopupButtons.OkCancel,
                };
                OnDisplayPopupPage(popup);
                break;
        }
    }

    public void Receive(PopupControlEventArgs eventArgs)
    {
        _logger.Information($"Receive() key={eventArgs.Key} value={eventArgs.ReturnValue}");

        RestoreModel();

        switch (eventArgs.Key)
        {
            case PublishedKey.JsDBKeyList:   // '#'-delimited planogram keys
                var pogKeyList = new List<string>(
                    eventArgs.ReturnValue.ToString().Trim()
                        .Split(new[] { '#' }, StringSplitOptions.RemoveEmptyEntries));

                _uiModel.SelectionModel.PogKeyList = pogKeyList;
                break;
        }

        SubscriptionManager.Publish(
            this,
            CommonConstants.SESSION_UIModel,
            JsonConvert.SerializeObject(_uiModel));

        UpdateSelectionLabel();
        _logger.Information("Finished Receive()");
    }

    public List<CommandAction> GetCommands()
    {
        return new List<CommandAction>
        {
            new CommandAction
            {
                Command         = "Process",
                Tooltip         = "Process",
                ImageCss        = StyleSelectors.ImageProcessOneBlue,
                CommandLocation = CommandLocations.TopRight,
                Enabled         = true,
                Visible         = true,
                RequiresPostBack = false,
            }
        };
    }

    public void DoCommand(CommandEventArgs e)
    {
        _logger.Information("Starting DoCommand()");
        try
        {
            switch (e.CommandName)
            {
                case "Process":
                    RestoreModel();
                    ProcessSelectedPlanograms();
                    break;
            }
        }
        catch (Exception ex)
        {
            _logger.Error(ex, "DoCommand Exception");
            OnDisplayMessage(new MessageEventArgs
            {
                Message         = "An unexpected error occurred.",
                EventType       = MessageEventTypes.Error,
                MessageLocation = MessageLocations.BottomLeft
            });
        }
        _logger.Information("Finished DoCommand()");
    }

    private void RestoreModel()
    {
        var json = SubscriptionManager
                       .GetPageStoreData(this, CommonConstants.SESSION_UIModel)?.ToString();
        _uiModel = !string.IsNullOrWhiteSpace(json)
            ? JsonConvert.DeserializeObject<MyControlModel>(json)
            : new MyControlModel();
    }

    private void UpdateSelectionLabel()
    {
        var count = _uiModel?.SelectionModel?.PogKeyList?.Count ?? 0;
        lblPogCount.Text = count > 0
            ? $"{count} planogram(s) selected."
            : "No planograms selected.";
    }

    private void ProcessSelectedPlanograms()
    {
        if (_uiModel.SelectionModel?.PogKeyList == null
            || _uiModel.SelectionModel.PogKeyList.Count == 0)
        {
            OnDisplayMessage(new MessageEventArgs
            {
                Message         = "Please select at least one planogram.",
                EventType       = MessageEventTypes.Warning,
                MessageLocation = MessageLocations.BottomLeft
            });
            return;
        }

        _commandFactory.YourOperation(_uiModel.SelectionModel.PogKeyList);
        SubscriptionManager.Publish(this, "_updated", 1);

        OnDisplayMessage(new MessageEventArgs
        {
            Message         = $"{_uiModel.SelectionModel.PogKeyList.Count} planogram(s) processed.",
            EventType       = MessageEventTypes.Success,
            MessageLocation = MessageLocations.BottomLeft
        });
    }
}
```

---

## Key Facts

| Explorer type | Page name string |
|---|---|
| Single-select | `"CKB Planogram Explorer"` |
| Multi-select | `"CKB Multi-select Planogram Explorer"` |

| Key received in `Receive()` | Meaning |
|---|---|
| `PublishedKey.JsDBKeyList` | `#`-delimited list of selected DBKeys (multi-select) |
| `PublishedKey.DBKey` | Single selected DBKey (single-select) |

The `JsDBKeyList` value is always `#`-delimited — split by `'#'` with `StringSplitOptions.RemoveEmptyEntries`.
