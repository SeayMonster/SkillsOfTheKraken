# Wiring a Standalone OA Control to Auto-Refresh on Planogram Selection

To make your standalone control automatically refresh whenever the user selects a planogram in the main OA explorer, you use the **SubscriptionManager** publish/subscribe system. The OA explorer publishes `PublishedKey.DBKey` when a planogram is selected; your control subscribes to that key and reacts in `OnMessageReceived`.

- **Single-select OA Explorer** (`"CKB Planogram Explorer"`) — publishes `PublishedKey.DBKey` (a plain integer)
- **Multi-select OA Explorer** (`"CKB Multi-select Planogram Explorer"`) — publishes `PublishedKey.JsDBKeyList` (a `#`-delimited list of DBKeys)

## Step 1 — Subscribe in the Constructor

Subscriptions must be registered in the **constructor**, not `OnInit`.

```csharp
public MyControlUI() : base()
{
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBKey);
}
```

## Step 2 — Override `OnMessageReceived`

```csharp
protected override void OnMessageReceived(object sender, DataStoreChangedEventArgs e)
{
    if (e.Key.Equals(SubscriptionManager.SubscribedKey(PublishedKey.DBKey),
                     StringComparison.OrdinalIgnoreCase))
    {
        var pogKey = SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey)?.ToString();
        if (!string.IsNullOrEmpty(pogKey))
        {
            LoadUI(Convert.ToInt32(pogKey));
        }
    }
}
```

`SubscriptionManager.SubscribedKey(...)` returns the decorated key name the framework uses internally — always use it inside the guard.

## Step 3 — Implement LoadUI

```csharp
private void LoadUI(int pogKey)
{
    _logger.Information($"Starting LoadUI() pogKey={pogKey}");
    try
    {
        var data = _commandFactory.GetMyData(pogKey);
        gvMyData.DataSource = data;
        gvMyData.DataBind();
    }
    catch (Exception ex) { _logger.Error(ex, "LoadUI Exception"); }
    _logger.Information("Finished LoadUI()");
}
```

## Full Minimal Scaffold

```csharp
public partial class MyControlUI : UserControlBase, ICommandManager
{
    private static readonly Logger _logger = ConfigurationHelper.CreateLogger("MyControl");
    private CommandFactory _commandFactory;

    public MyControlUI() : base()
    {
        SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBKey);
    }

    protected override void OnInit(EventArgs e)
    {
        base.OnInit(e);
        var customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");
        _commandFactory  = new CommandFactory(KBDbSupport, customSchema, _logger);
    }

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        if (!IsPostBack)
        {
            var pogKey = SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey)?.ToString();
            if (!string.IsNullOrEmpty(pogKey))
                LoadUI(Convert.ToInt32(pogKey));
        }
    }

    protected override void OnMessageReceived(object sender, DataStoreChangedEventArgs e)
    {
        if (e.Key.Equals(SubscriptionManager.SubscribedKey(PublishedKey.DBKey),
                         StringComparison.OrdinalIgnoreCase))
        {
            var pogKey = SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey)?.ToString();
            if (!string.IsNullOrEmpty(pogKey))
                LoadUI(Convert.ToInt32(pogKey));
        }
    }

    private void LoadUI(int pogKey)
    {
        _logger.Information($"Starting LoadUI() pogKey={pogKey}");
        try
        {
            var data = _commandFactory.GetMyData(pogKey);
            gvMyData.DataSource = data;
            gvMyData.DataBind();
        }
        catch (Exception ex) { _logger.Error(ex, "LoadUI Exception"); }
        _logger.Information("Finished LoadUI()");
    }

    public List<CommandAction> GetCommands() => new List<CommandAction>();
    public void DoCommand(CommandEventArgs e) { }
}
```

## Key Rules

1. **Constructor, not OnInit** — `AddKeyToSubscribe` must go in the constructor or the framework misses the first message.
2. **Always use `SubscriptionManager.SubscribedKey(...)` in the guard** — comparing against the raw constant will not match.
3. **Also read on `!IsPostBack`** — use `GetPageStoreData` in `OnLoad` to pick up an already-selected value.
4. **Logging** — every method that does significant work gets Start/Finish `_logger.Information()` calls.
5. **CommandFactory** — instantiate in `OnInit` (where `KBDbSupport` is available), not in the constructor.
