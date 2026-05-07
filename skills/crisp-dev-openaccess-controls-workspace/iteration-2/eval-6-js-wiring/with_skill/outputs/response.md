# Wiring JavaScript in an OA Control

## The Problem with `$(document).ready()`

`$(document).ready()` (and the `(function($){...}(jQuery))` IIFE) both fail silently in OA controls. The reason is timing: **the OA framework loads jQuery after the page's `<script>` tags have already executed**. At the moment your script file is parsed, `jQuery` is still undefined, so the IIFE captures `undefined` as `$` and `$(document).ready()` never registers.

There is no error thrown — it just does nothing.

---

## The Correct Pattern: `Sys.Application.add_load`

Use `Sys.Application.add_load` instead. This is the ASP.NET AJAX equivalent of `document.ready`. It fires after the ScriptManager has finished loading all framework scripts, including jQuery — so jQuery is guaranteed to be available when your callback runs.

```javascript
console.log('[MyControl] MyControl.js loaded');   // fires immediately on file parse

Sys.Application.add_load(function () {
    console.log('[MyControl] Sys.Application.add_load fired');

    var $ = jQuery;   // assign locally — do not rely on $ being globally aliased

    var $source = $('#lbSource');
    var $dest   = $('#lbDest');
    var $hdn    = $('#hdnDestItems');
    var $btn    = $('#btnMoveToNew');

    console.log('[MyControl] btnMoveToNew found:', $btn.length);  // 0 = ID mismatch

    $btn.on('click', function () {
        console.log('[MyControl] button clicked');
        // ... your initialization and interaction code ...
    });
});
```

> **Do not use `$(document).ready()`** — it fails silently because jQuery is undefined when your script file executes.

---

## Full Wiring Checklist

Getting JS to work in an OA standalone control requires four things to be correct simultaneously.

### 1. JS file lives in `Javascript\MyControl.js`

Never put initialization code in inline `<script>` blocks in the ASCX. External files are cached, debuggable in DevTools, and required for `ClientIDMode="Static"` IDs to work (ASP.NET does not process `<%= %>` expressions in `.js` files).

### 2. ASCX has a full `<html>/<head>/<body>` structure

The `<script>` tag goes at the bottom of `<body>` using a relative path:

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

### 3. Controls the JS references must have `ClientIDMode="Static"`

Because the JS file is static, ASP.NET will not process `<%= control.ClientID %>` inside it. Every control you need to select by ID must have a predictable, stable ID:

```aspx
<asp:ListBox runat="server" ID="lbSource"
    SelectionMode="Multiple" Rows="15" Width="220px"
    CssClass="cx-listbox" ClientIDMode="Static" />

<asp:HiddenField runat="server" ID="hdnDestItems" ClientIDMode="Static" />

<asp:Button runat="server" ID="btnMoveToNew" Text="Move &#x2192;" CssClass="cx-btn"
    UseSubmitBehavior="false" OnClientClick="return false;" ClientIDMode="Static" />
```

The `UseSubmitBehavior="false"` + `OnClientClick="return false;"` combination on `asp:Button` is also required for client-only buttons — it prevents the button from triggering a postback while still allowing jQuery's `.on('click', ...)` listener to fire normally.

### 4. File is deployed via `CopyWebUI.bat` and registered in the `.csproj`

**In `.csproj`:**

```xml
<Content Include="Javascript\MyControl.js" />
```

**In `CopyWebUI.bat`:**

```bat
copy "%PROJECT_DIR%Javascript\MyControl.js" "%WEB_APPLICATION_DIR%\Custom\scripts"
```

The `Custom\scripts` directory is created by the `mkdir` guards at the top of the bat file.

---

## Registering Script from Code-Behind

If you need to inject a startup or diagnostic script block from C#, use `ScriptManager.RegisterClientScriptBlock` in `OnPreRender`. **Do not use `Page.ClientScript.RegisterClientScriptBlock`** — it is silently ignored when a ScriptManager is present (which the OA framework always has).

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

## Quick Diagnostic Steps

If your `Sys.Application.add_load` callback is not firing or selectors are returning empty:

1. Add `console.log('[MyControl] MyControl.js loaded')` at the top of the JS file — if this does not appear in DevTools console, the script tag src path is wrong or the file was not copied by `CopyWebUI.bat`.
2. Add `console.log('[MyControl] add_load fired')` at the top of the `add_load` callback — if the first log appears but this one does not, `Sys` is not defined (unlikely but indicates the ScriptManager is missing from the host page).
3. Log `$btn.length` after each selector — a value of `0` means the element ID in the JS does not match the rendered ID. Check that `ClientIDMode="Static"` is set on the control in the ASCX.
