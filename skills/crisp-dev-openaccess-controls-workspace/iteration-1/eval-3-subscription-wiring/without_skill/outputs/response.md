# Wiring a Standalone OA Control to Auto-Refresh on Planogram Selection

## Overview

The OA platform uses a publish/subscribe system called `SubscriptionManager` to synchronize state between the main OA explorer and any controls co-located on the same page. When the user selects a planogram in the explorer, it publishes the selected key under `PublishedKey.DBKey`. A standalone control auto-refreshes by subscribing to that key and reacting when it changes.

## Step 1 — Declare the subscription in the constructor

```csharp
public MyControl() : base()
{
    SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBKey);
}
```

This call must happen in the constructor (not `OnInit` or `OnLoad`) so the framework has the subscription list available before the page lifecycle begins.

## Step 2 — Override OnMessageReceived

```csharp
protected override void OnMessageReceived(object sender, DataStoreChangedEventArgs e)
{
    if (e.Key.Equals(
            SubscriptionManager.SubscribedKey(PublishedKey.DBKey),
            StringComparison.OrdinalIgnoreCase))
    {
        LoadUI();
    }
    else
    {
        base.OnMessageReceived(sender, e);
    }
}
```

## Step 3 — Read the current planogram key inside LoadUI

```csharp
private void LoadUI()
{
    var rawKey = SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey);

    if (string.IsNullOrWhiteSpace(rawKey))
        return;

    var pogKey = Convert.ToInt32(rawKey);
    var data   = _commandFactory.GetMyData(pogKey);
    BindUI(data);
}
```

Call `LoadUI` from `OnLoad` only on `!IsPostBack`:

```csharp
protected override void OnLoad(EventArgs e)
{
    base.OnLoad(e);
    _commandFactory = new CommandFactory(_dbSupport, customSchema, _logger);

    if (!IsPostBack)
        LoadUI();
}
```

## Complete skeleton

```csharp
public partial class MyPogControl : UserControlBase, ICommandManager
{
    private CommandFactory _commandFactory;

    public MyPogControl() : base()
    {
        SubscriptionManager.AddKeyToSubscribe(PublishedKey.DBKey);
    }

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        _commandFactory = new CommandFactory(_dbSupport,
            ConfigurationHelper.GetConfigSetting("CustomSchema"), _logger);

        if (!IsPostBack)
            LoadUI();
    }

    protected override void OnMessageReceived(object sender, DataStoreChangedEventArgs e)
    {
        if (e.Key.Equals(
                SubscriptionManager.SubscribedKey(PublishedKey.DBKey),
                StringComparison.OrdinalIgnoreCase))
        {
            LoadUI();
        }
        else
        {
            base.OnMessageReceived(sender, e);
        }
    }

    private void LoadUI()
    {
        var rawKey = SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey);
        if (string.IsNullOrWhiteSpace(rawKey)) return;

        var pogKey = Convert.ToInt32(rawKey);
        var data   = _commandFactory.GetMyData(pogKey);
        BindUI(data);
    }
}
```

## Key points

| Concern | Correct approach |
|---|---|
| Where to subscribe | Constructor via `AddKeyToSubscribe` |
| How to react | Override `OnMessageReceived`; compare using `SubscriptionManager.SubscribedKey()` |
| How to read the value | `SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey)` |
| When to call LoadUI on postback | Only on `!IsPostBack` from `OnLoad` |
| Publishing your own changes | `SubscriptionManager.Publish(this, "_updated", 1)` after a save |
