# Why `$(document).ready()` Does Not Fire in an OA Control

## Root Cause

The OA platform (Cantactix/BlueYonder OpenAccess) is an ASP.NET WebForms application built on top of ASP.NET AJAX (the `ScriptManager` / `Sys` stack). The key fact is:

**The OA framework loads jQuery after your control's static `.js` file has already been parsed and executed.**

Your static `.js` file is referenced by a `<script>` tag in the ASCX's `<body>`:

```aspx
<script type="text/javascript" src="custom/scripts/MyControl.js"></script>
```

The browser executes that script synchronously at parse time. At that moment `jQuery` is `undefined` — the framework hasn't loaded it yet. So:

- `$(document).ready(...)` throws or silently does nothing because `$` is not yet the jQuery function.
- `(function($){...}(jQuery))` immediately-invoked form also fails — same reason.

---

## The Correct Pattern: `Sys.Application.add_load`

ASP.NET AJAX provides `Sys.Application.add_load`, which fires after the `ScriptManager` has finished loading all framework scripts — including jQuery — and after all UpdatePanel partials are done rendering. It also re-fires after every partial-page update (UpdatePanel postback).

### JS file structure

```javascript
console.log('[MyControl] MyControl.js loaded');   // fires immediately on file parse

Sys.Application.add_load(function () {
    console.log('[MyControl] Sys.Application.add_load fired');

    var $ = jQuery;   // jQuery is available here — alias it to $ for convenience

    var $source = $('#lbSource');
    var $dest   = $('#lbDest');
    var $hdn    = $('#hdnDestItems');
    var $btnNew = $('#btnMoveToNew');

    console.log('[MyControl] btnMoveToNew found:', $btnNew.length);  // 0 = ID mismatch

    $btnNew.on('click', function () {
        console.log('[MyControl] btnMoveToNew clicked');
        // ... your logic here ...
    });
});
```

The `var $ = jQuery;` alias on the first line inside the callback is important. It makes the rest of the function read exactly like standard jQuery code without any other changes.

---

## Why `ClientIDMode="Static"` Is Also Required

External `.js` files are static text — ASP.NET does not run the template engine on them, so `<%= control.ClientID %>` expressions are not expanded. If your controls don't have stable, predictable IDs, your `$('#someId')` selectors will find nothing.

Add `ClientIDMode="Static"` to every control that your JS file selects by ID:

```aspx
<asp:ListBox runat="server" ID="lbCurrentStores"
    SelectionMode="Multiple" Rows="15" Width="220px"
    CssClass="cx-listbox" ClientIDMode="Static" />

<asp:HiddenField runat="server" ID="hdnNewStores" ClientIDMode="Static" />

<asp:Button runat="server" ID="btnMoveToNew" Text="Move &#x2192;" CssClass="cx-btn"
    UseSubmitBehavior="false" OnClientClick="return false;" ClientIDMode="Static" />
```

---

## Script Tag Placement in the ASCX

```aspx
<%@ Control Language="C#" AutoEventWireup="true"
    CodeBehind="MyControlUI.ascx.cs" Inherits="MyProject.Views.MyControlUI" %>

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

---

## Registering Script Blocks from Code-Behind

If you need to inject a startup script block from C#, use `ScriptManager.RegisterClientScriptBlock` in `OnPreRender`. **Do not use `Page.ClientScript.RegisterClientScriptBlock`** — it is silently ignored when a `ScriptManager` is on the page, which the OA framework always has.

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

---

## Summary

| What you tried | Why it fails |
|---|---|
| `$(document).ready(...)` | `jQuery`/`$` is undefined when the static `.js` file executes |
| `(function($){...}(jQuery))` IIFE | Same — `jQuery` is not yet loaded |
| `Page.ClientScript.RegisterClientScriptBlock` from code-behind | Silently dropped when a ScriptManager is present |

| What to use instead | Why it works |
|---|---|
| `Sys.Application.add_load(function() { var $ = jQuery; ... })` | Runs after the ScriptManager has loaded jQuery and all framework scripts; also re-fires after UpdatePanel partial postbacks |
| `ClientIDMode="Static"` on every control your JS selects by ID | External `.js` files are not template-processed; IDs must be stable and predictable |
| `ScriptManager.RegisterClientScriptBlock(...)` in `OnPreRender` | Correct injection point when generating script from code-behind in an UpdatePanel context |
