# Multi-Select Planogram Picker in a Standalone OA Control

This guide covers everything you need to add the built-in OA multi-select planogram explorer popup to a standalone control (`UserControlBase`). The pattern uses `PublishedKey.JsDBKeyList` to receive the selected planogram keys as a `#`-delimited string.

---

## Which Pattern to Use

**Standalone control** + **multi-select** + **built-in OA explorer** → `IPopupControlSubscriber` + `"CKB Multi-select Planogram Explorer"`.

Do **not** use:
- `"CKB Planogram Explorer"` — single-select; publishes `PublishedKey.DBKey`, not `JsDBKeyList`
- A custom ASCX popup (`IPopupCommandManager`) — for fully custom selection UIs only

---

## Step 1 — Class Declaration

```csharp
public partial class MyControlUI : UserControlBase, IPopupControlSubscriber, ICommandManager
```

---

## Step 2 — Constructor Subscriptions

Register the three keys the built-in multi-select explorer publishes. **Must be in the constructor**, not `OnInit` — the framework resolves published keys before the page lifecycle runs.

```csharp
public MyControlUI() : base()
{
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.HierarchyDBKeyList);
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.JsDBKeyList);
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBStatusList);
}
```

| Key | What it carries |
|---|---|
| `PublishedKey.HierarchyDBKeyList` | Hierarchy node selections from the explorer tree |
| `PublishedKey.JsDBKeyList` | Selected planogram DBKeys, `#`-delimited |
| `PublishedKey.DBStatusList` | Status filter selections from the explorer |

---

## Step 3 — ASCX Markup (trigger button)

```aspx
<asp:LinkButton ID="lnkbtnSelectPlanogram" CommandName="ObjectExplorerSpace"
    OnClick="PlanogramList_ButtonClick" CssClass="link-button-icon-label">
    <asp:Label ID="lblSelectPlanogram" Text="Select Planogram(s)" />
</asp:LinkButton>
```

---

## Step 4 — Open the Popup

```csharp
protected void PlanogramList_ButtonClick(object sender, EventArgs e)
{
    switch (((LinkButton)sender).CommandName)
    {
        case "ObjectExplorerSpace":
            var pageKey = _commandFactory.GetPageKey("CKB Multi-select Planogram Explorer");
            var popupPageEventArgs = new PopupPageEventArgs
            {
                PageKey          = pageKey,
                Title            = "Select Planogram(s)",
                AutoHeight       = true,
                HideControlTitle = true,
                HidePageTitle    = true,
                Buttons          = PopupButtons.OkCancel,
            };
            OnDisplayPopupPage(popupPageEventArgs);
            break;
    }
}
```

- `PageKey` is resolved by name from the database via `ckbcustom.cx_page_key_get` — never hardcode the integer key.
- The page name `"CKB Multi-select Planogram Explorer"` must match the `Name` column in `ix_web_page` exactly.

---

## Step 5 — Receive the Selected Keys

```csharp
public void Receive(PopupControlEventArgs eventArgs)
{
    _logger.Information($"Receive() key: {eventArgs.Key} value: {eventArgs.ReturnValue}");

    switch (eventArgs.Key)
    {
        case PublishedKey.JsDBKeyList:  // selected planogram DBKeys, '#'-delimited
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

    PublishModel();
}
```

---

## Complete Code-Behind Scaffold

```csharp
public partial class MyControlUI : UserControlBase, IPopupControlSubscriber, ICommandManager
{
    private static readonly Logger _logger = ConfigurationHelper.CreateLogger("MyControl");
    private CommandFactory _commandFactory;
    private MyControlModel _uiModel;
    private string _customSchema;

    public MyControlUI() : base()
    {
        SubscriptionManager.AddKeyToSubscribe(PublishedKey.HierarchyDBKeyList);
        SubscriptionManager.AddKeyToSubscribe(PublishedKey.JsDBKeyList);
        SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBStatusList);
    }

    protected override void OnInit(EventArgs e)
    {
        base.OnInit(e);
        _customSchema   = ConfigurationHelper.GetConfigSetting("CustomSchema");
        _commandFactory = new CommandFactory(KBDbSupport, _customSchema, _logger);

        var json = SubscriptionManager.GetPageStoreData(this, CommonConstants.SESSION_UIModel)?.ToString();
        _uiModel = string.IsNullOrEmpty(json)
            ? new MyControlModel()
            : JsonConvert.DeserializeObject<MyControlModel>(json);
    }

    protected override void OnPreRender(EventArgs e)
    {
        base.OnPreRender(e);
        // Bind selection summary, grids, etc. from _uiModel here
    }

    private void PublishModel()
    {
        SubscriptionManager.Publish(this, CommonConstants.SESSION_UIModel,
            JsonConvert.SerializeObject(_uiModel));
    }

    protected void PlanogramList_ButtonClick(object sender, EventArgs e)
    {
        switch (((LinkButton)sender).CommandName)
        {
            case "ObjectExplorerSpace":
                var pageKey = _commandFactory.GetPageKey("CKB Multi-select Planogram Explorer");
                OnDisplayPopupPage(new PopupPageEventArgs
                {
                    PageKey          = pageKey,
                    Title            = "Select Planogram(s)",
                    AutoHeight       = true,
                    HideControlTitle = true,
                    HidePageTitle    = true,
                    Buttons          = PopupButtons.OkCancel,
                });
                break;
        }
    }

    public void Receive(PopupControlEventArgs eventArgs)
    {
        _logger.Information($"Receive() key: {eventArgs.Key} value: {eventArgs.ReturnValue}");

        switch (eventArgs.Key)
        {
            case PublishedKey.JsDBKeyList:
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

        PublishModel();
    }

    public List<CommandAction> GetCommands()
    {
        return new List<CommandAction>
        {
            new CommandAction()
            {
                Command          = "Submit",
                Tooltip          = "Submit",
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
        try
        {
            switch (e.CommandName)
            {
                case "Submit":
                    Submit();
                    break;
            }
        }
        catch (Exception ex) { _logger.Error(ex, "DoCommand Exception"); }
    }

    private void Submit()
    {
        _logger.Information("Starting Submit()");

        if (_uiModel.SelectionModel.PogKeys == null || _uiModel.SelectionModel.PogKeys.Rows.Count == 0)
        {
            OnDisplayMessage(new MessageEventArgs()
            {
                Message         = "Please select at least one planogram.",
                EventType       = MessageEventTypes.Error,
                MessageLocation = MessageLocations.BottomLeft
            });
            return;
        }

        // Pass _uiModel.SelectionModel.PogKeys to your stored procedure here

        OnDisplayMessage(new MessageEventArgs()
        {
            Message         = "Operation completed successfully.",
            EventType       = MessageEventTypes.Success,
            MessageLocation = MessageLocations.BottomLeft
        });
        _logger.Information("Finished Submit()");
    }
}
```

---

## Checklist

| Item | Required |
|---|---|
| Class implements `IPopupControlSubscriber` and `ICommandManager` | Yes |
| Constructor calls `AddKeyToSubscribe` for `HierarchyDBKeyList`, `JsDBKeyList`, `DBStatusList` | Yes |
| Button `CommandName="ObjectExplorerSpace"` wired to click handler | Yes |
| `GetPageKey("CKB Multi-select Planogram Explorer")` — not `"CKB Planogram Explorer"` | Yes |
| `Receive()` guards on `PublishedKey.JsDBKeyList` and splits on `'#'` | Yes |
| `PublishModel()` called at the end of `Receive()` | Yes |

---

## Common Mistakes

**Using the wrong page name.** `"CKB Planogram Explorer"` is single-select and publishes `PublishedKey.DBKey`. Multi-select uses `"CKB Multi-select Planogram Explorer"` and publishes `PublishedKey.JsDBKeyList`.

**Subscribing in `OnInit` instead of the constructor.** Subscriptions added in `OnInit` are too late — the framework has already resolved published keys.

**Forgetting `IPopupControlSubscriber`.** Without this interface, `Receive()` is never called and the selection is silently dropped.

**Not splitting on `'#'`.** `ReturnValue` for `JsDBKeyList` is a raw string like `"1234#5678#9012"` — you must split it.

**Not calling `PublishModel()` after `Receive()`.** The model update will be lost on the next postback.
