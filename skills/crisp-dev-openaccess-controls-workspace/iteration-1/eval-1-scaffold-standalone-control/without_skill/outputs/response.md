# StoreConfigControl — Standalone OA Control

Below is a complete implementation of a standalone OpenAccess control called `StoreConfigControl`, following the patterns established in this codebase.

## File: `Views/StoreConfigControl.ascx.cs`

```csharp
using JDA.Intactix.IKB.DataAccess;
using JDA.Intactix.IKB.Web.Framework;
using JDA.Intactix.IKB.Web.UI;
using JDA.Intactix.Web.Common;
using JDA.Intactix.Web.Framework;
using JDA.Intactix.Web.Framework.Common;

using Serilog.Core;

using StoreConfigControl.HelperClasses;
using StoreConfigControl.Models;

using System;
using System.Collections.Generic;

namespace StoreConfigControl.Views
{
    public partial class StoreConfigControl : UserControlBase, ICommandManager
    {
        private static readonly Logger _logger =
            ConfigurationHelper.CreateLogger("StoreConfigControl");

        private CommandFactory   _commandFactory;
        private StoreConfigModel _uiModel;
        private IKBDbSupport     _dbSupport = new IKBDbSupport(Helper.CurrentUser);

        protected override void OnInit(EventArgs e)
        {
            base.OnInit(e);
            SubscriptionManager.AddKeyToPublish("_updated");
        }

        protected override void OnLoad(EventArgs e)
        {
            _logger.Information("Starting OnLoad()");
            base.OnLoad(e);

            var customSchema = ConfigurationHelper.GetConfigSetting("CustomSchema");
            _commandFactory  = new CommandFactory(_dbSupport, customSchema, _logger);

            if (!IsPostBack)
                LoadUI();

            _logger.Information("Finished OnLoad()");
        }

        private void LoadUI()
        {
            _logger.Information("Starting LoadUI()");
            _uiModel = new StoreConfigModel();
            _logger.Information("Finished LoadUI()");
        }

        public List<CommandAction> GetCommands()
        {
            return new List<CommandAction>
            {
                new CommandAction()
                {
                    Command          = "Save",
                    Tooltip          = "Save Store Configuration",
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
            _logger.Information($"Starting DoCommand() — CommandName: {e.CommandName}");

            try
            {
                switch (e.CommandName)
                {
                    case "Save":
                        ExecuteSave();
                        break;
                }
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "DoCommand Exception");
                OnDisplayMessage(new MessageEventArgs()
                {
                    Message         = "An unexpected error occurred while saving.",
                    EventType       = MessageEventTypes.Error,
                    MessageLocation = MessageLocations.BottomLeft
                });
            }

            _logger.Information("Finished DoCommand()");
        }

        private void ExecuteSave()
        {
            _logger.Information("Starting ExecuteSave()");

            _uiModel = BuildModelFromForm();
            _commandFactory.SaveStoreConfig(_uiModel);

            SubscriptionManager.Publish(this, "_updated", 1);

            OnDisplayMessage(new MessageEventArgs()
            {
                Message         = "Store configuration saved successfully.",
                EventType       = MessageEventTypes.Success,
                MessageLocation = MessageLocations.BottomLeft
            });

            _logger.Information("Finished ExecuteSave()");
        }

        private StoreConfigModel BuildModelFromForm()
        {
            return new StoreConfigModel
            {
                StoreName   = txtStoreName.Text.Trim(),
                StoreNumber = txtStoreNumber.Text.Trim(),
                Region      = txtRegion.Text.Trim(),
                IsActive    = chkActive.Checked,
            };
        }
    }
}
```
