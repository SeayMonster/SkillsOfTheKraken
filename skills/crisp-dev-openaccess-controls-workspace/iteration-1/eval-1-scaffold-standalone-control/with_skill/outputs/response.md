# StoreConfigControl — Standalone OA Control Scaffold

Complete scaffold for a new standalone OpenAccess control named **StoreConfigControl**. Inherits `UserControlBase`, implements `ICommandManager`, exposes a **Save** toolbar button, shows a success message on click.

## Project Folder Layout

```
StoreConfigControl\
  StoreConfigControl.csproj
  CopyWebUI.bat
  Libraries\               ← copy from SampleOAProject\Libraries\
  Config\
    CrispCustomizations.config
  CSS\
    StoreConfigControl.css
  Javascript\
    StoreConfigControl.js
  Views\
    StoreConfigControlUI.ascx
    StoreConfigControlUI.ascx.cs
    StoreConfigControlUI.ascx.designer.cs
  HelperClasses\
    CommandFactory.cs
    ConfigurationHelper.cs
  Models\
    StoreConfigModel.cs
  SQL\
    Stored Procedures\
    Tables\
```

## Models\StoreConfigModel.cs

```csharp
namespace StoreConfigControl.Models
{
    public class StoreConfigModel
    {
        public int StoreDBKey { get; set; }
        public string ConfigValue { get; set; }
    }
}
```

## HelperClasses\ConfigurationHelper.cs

```csharp
using System;
using System.Configuration;
using System.IO;
using System.Web;
using Serilog;
using Serilog.Core;
using Serilog.Sinks.RollingFileAlternate;

namespace StoreConfigControl.HelperClasses
{
    public static class ConfigurationHelper
    {
        public static string GetConfigSetting(string settingName)
        {
            try
            {
                var path = HttpContext.Current.Request.MapPath("~/Custom/Config/CrispCustomizations.config");
                if (!File.Exists(path)) return null;
                var map = new ExeConfigurationFileMap { ExeConfigFilename = path };
                var section = (AppSettingsSection)ConfigurationManager
                    .OpenMappedExeConfiguration(map, ConfigurationUserLevel.None)
                    .GetSection("appSettings");
                return section?.Settings[settingName]?.Value;
            }
            catch (Exception) { return null; }
        }

        public static Logger CreateLogger(string featureName)
        {
            var logDir = HttpContext.Current.Server.MapPath($"~/Logging/{featureName}/");
            if (!Directory.Exists(logDir)) Directory.CreateDirectory(logDir);
            return new LoggerConfiguration()
                .WriteTo.RollingFileAlternate(
                    logDir,
                    logFilePrefix: $"{Environment.UserName?.Replace('\\', '-') ?? "UnknownUser"}",
                    minimumLevel: Serilog.Events.LogEventLevel.Debug,
                    outputTemplate: "{Timestamp:MM-dd-yyyy HH:mm:ss} [{Level}] {Message}{NewLine}{Exception}",
                    fileSizeLimitBytes: 1048576 / 8,
                    retainedFileCountLimit: 1)
                .CreateLogger();
        }
    }
}
```

## Views\StoreConfigControlUI.ascx.cs

```csharp
#region usings
using JDA.Intactix.IKB.Web.Framework;
using JDA.Intactix.IKB.Web.UI;
using JDA.Intactix.Web.Framework;

using Newtonsoft.Json;
using Serilog.Core;

using StoreConfigControl.HelperClasses;
using StoreConfigControl.Models;

using System;
using System.Collections.Generic;
#endregion

namespace StoreConfigControl.Views
{
    public partial class StoreConfigControlUI : UserControlBase, ICommandManager
    {
        private static readonly Logger _logger = ConfigurationHelper.CreateLogger("StoreConfig");

        private CommandFactory   _commandFactory;
        private StoreConfigModel _uiModel;
        private string           _customSchema;

        public StoreConfigControlUI() : base()
        {
            SubscriptionManager.AddKeyToPublish("_updated");
        }

        protected override void OnInit(EventArgs e)
        {
            base.OnInit(e);

            _customSchema   = ConfigurationHelper.GetConfigSetting("CustomSchema");
            _commandFactory = new CommandFactory(KBDbSupport, _customSchema, _logger);

            var json = SubscriptionManager.GetPageStoreData(this, CommonConstants.SESSION_UIModel)?.ToString();
            _uiModel = string.IsNullOrEmpty(json)
                ? new StoreConfigModel()
                : JsonConvert.DeserializeObject<StoreConfigModel>(json);
        }

        protected override void OnLoad(EventArgs e)
        {
            _logger.Information("Starting OnLoad()");
            base.OnLoad(e);
            if (!IsPostBack)
                LoadUI();
            _logger.Information("Finished OnLoad()");
        }

        protected override void OnPreRender(EventArgs e)
        {
            base.OnPreRender(e);
            if (!Page.IsPostBack)
                txtConfigValue.Text = _uiModel.ConfigValue ?? string.Empty;
        }

        private void LoadUI()
        {
            _logger.Information("Starting LoadUI()");
            var storeKeyStr = SubscriptionManager.GetPageStoreData(this, PublishedKey.DBKey)?.ToString();
            _uiModel = new StoreConfigModel
            {
                StoreDBKey = int.TryParse(storeKeyStr, out var k) ? k : 0
            };
            PublishModel();
            _logger.Information("Finished LoadUI()");
        }

        private void PublishModel()
        {
            SubscriptionManager.Publish(this, CommonConstants.SESSION_UIModel,
                JsonConvert.SerializeObject(_uiModel));
        }

        public List<CommandAction> GetCommands()
        {
            return new List<CommandAction>
            {
                new CommandAction()
                {
                    Command          = "Save",
                    Tooltip          = "Save",
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
                    case "Save":
                        Save();
                        break;
                }
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "DoCommand Exception");
            }
            _logger.Information("Finished DoCommand()");
        }

        private void Save()
        {
            _logger.Information("Starting Save()");

            _uiModel.ConfigValue = txtConfigValue.Text.Trim();
            PublishModel();

            SubscriptionManager.Publish(this, "_updated", 1);

            OnDisplayMessage(new MessageEventArgs()
            {
                Message         = "Store configuration saved successfully.",
                EventType       = MessageEventTypes.Success,
                MessageLocation = MessageLocations.BottomLeft
            });

            _logger.Information("Finished Save()");
        }
    }
}
```

## CopyWebUI.bat

```bat
exit 0
SET PROJECT_DIR=%~1%
SET WEB_APPLICATION_DIR=C:\Program Files (x86)\JDA\Intactix\Intactix Knowledge Base\Open Access

if not exist "%WEB_APPLICATION_DIR%\Custom"         mkdir "%WEB_APPLICATION_DIR%\Custom"
if not exist "%WEB_APPLICATION_DIR%\Custom\Config"  mkdir "%WEB_APPLICATION_DIR%\Custom\Config"
if not exist "%WEB_APPLICATION_DIR%\Custom\Styles"  mkdir "%WEB_APPLICATION_DIR%\Custom\Styles"
if not exist "%WEB_APPLICATION_DIR%\Custom\scripts" mkdir "%WEB_APPLICATION_DIR%\Custom\scripts"

copy "%PROJECT_DIR%Views\*.ascx"                      "%WEB_APPLICATION_DIR%\Custom"
copy "%PROJECT_DIR%bin\StoreConfigControl.dll"        "%WEB_APPLICATION_DIR%\bin"
copy "%PROJECT_DIR%CSS\StoreConfigControl.css"        "%WEB_APPLICATION_DIR%\Custom\Styles"
copy "%PROJECT_DIR%Javascript\StoreConfigControl.js"  "%WEB_APPLICATION_DIR%\Custom\scripts"
copy "%PROJECT_DIR%Config\CrispCustomizations.config" "%WEB_APPLICATION_DIR%\Custom\Config"
```

`exit 0` on line 1 disables the copy on machines without OA installed. Comment it out on dev.
