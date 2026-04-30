# WPF UI Patterns Reference

When a UI is needed, use WPF (Windows Presentation Foundation) — NOT Windows Forms.

---

## Project Setup Changes for WPF

### .csproj changes

Add `OutputType` as `WinExe` (if the project is a standalone app) or keep `Library` (if the WPF
window is launched from a class library script). Add WPF-specific property groups:

```xml
<PropertyGroup>
  <OutputType>Library</OutputType>             <!-- or WinExe for standalone -->
  <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
  <UseWPF>true</UseWPF>
</PropertyGroup>
```

### Additional Assembly References

```xml
<Reference Include="PresentationCore" />
<Reference Include="PresentationFramework" />
<Reference Include="System.Xaml" />
<Reference Include="WindowsBase" />
```

---

## Folder Structure (with WPF)

```
MyProjectName\
├── HelperClasses\
│   ├── CommandFactory.cs
│   ├── ConfigurationHelper.cs
│   └── CommonConstants.cs
├── Libraries\
├── Models\
├── Views\
│   ├── MainWindow.xaml         ← WPF Window XAML
│   ├── MainWindow.xaml.cs      ← Code-behind
│   └── (additional windows or UserControls as needed)
├── SQL\
│   └── Stored Procedures\
├── MyProject.cs                ← main script class, launches UI
└── ...
```

---

## Launching WPF Window from Script Class

```csharp
// In MyProjectClass.cs (the Script-inheriting class)
public override void Run(bool isSilentMode = true)
{
    _logger.Information($"Starting Run()");

    try
    {
        Init();

        var window = new Views.MainWindow(_commandFactory, _logger);

        // Required: WPF needs an STA thread — JDA scripts run STA, but wrap to be safe
        var app = new System.Windows.Application();
        app.Run(window);
    }
    catch (Exception ex)
    {
        _logger.Error(ex, "Run Exception");
        throw;
    }

    _logger.Information($"Finished Run()");
}
```

---

## MainWindow.xaml — Boilerplate

```xml
<Window x:Class="MyProjectAssembly.Views.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="My Project" Height="450" Width="800"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip">

    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <!-- Header / Filters -->
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <Label Content="Filter:" VerticalAlignment="Center" />
            <ComboBox x:Name="cmbFilter" Width="200" Margin="5,0,0,0" />
            <Button x:Name="btnLoad" Content="Load" Width="80" Margin="10,0,0,0"
                    Click="btnLoad_Click" />
        </StackPanel>

        <!-- Data Grid -->
        <DataGrid Grid.Row="1" x:Name="dgResults"
                  AutoGenerateColumns="True"
                  IsReadOnly="True"
                  AlternatingRowBackground="AliceBlue"
                  GridLinesVisibility="Horizontal" />

        <!-- Footer / Actions -->
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right"
                    Margin="0,10,0,0">
            <Button x:Name="btnExport" Content="Export" Width="80" Margin="0,0,10,0"
                    Click="btnExport_Click" />
            <Button x:Name="btnClose" Content="Close" Width="80"
                    Click="btnClose_Click" />
        </StackPanel>
    </Grid>
</Window>
```

---

## MainWindow.xaml.cs — Code-Behind Pattern

```csharp
#region
using MyProjectAssembly.HelperClasses;

using Serilog.Core;

using System;
using System.Data;
using System.Windows;
#endregion

namespace MyProjectAssembly.Views
{
    public partial class MainWindow : Window
    {
        private readonly CommandFactory _commandFactory;
        private readonly Logger _logger;

        public MainWindow(CommandFactory commandFactory, Logger logger)
        {
            _commandFactory = commandFactory;
            _logger = logger;

            InitializeComponent();
            LoadFilters();
        }

        private void LoadFilters()
        {
            _logger.Information($"Starting LoadFilters()");

            try
            {
                var filters = _commandFactory.GetFilterData();
                cmbFilter.ItemsSource = filters.DefaultView;
                cmbFilter.DisplayMemberPath = "FilterName";
                cmbFilter.SelectedValuePath = "FilterKey";
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "LoadFilters Exception");
                MessageBox.Show("Failed to load filters.", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }

            _logger.Information($"Finished LoadFilters()");
        }

        private void btnLoad_Click(object sender, RoutedEventArgs e)
        {
            _logger.Information($"Starting btnLoad_Click()");

            try
            {
                if (cmbFilter.SelectedValue == null)
                {
                    MessageBox.Show("Please select a filter.", "Validation",
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                var selectedKey = cmbFilter.SelectedValue.ToString();
                var results = _commandFactory.GetResultData(selectedKey);
                dgResults.ItemsSource = results.DefaultView;

                _logger.Information($"Loaded {results.Rows.Count} rows");
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "btnLoad_Click Exception");
                MessageBox.Show($"Error loading data: {ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }

            _logger.Information($"Finished btnLoad_Click()");
        }

        private void btnExport_Click(object sender, RoutedEventArgs e)
        {
            _logger.Information($"Starting btnExport_Click()");

            try
            {
                var dialog = new Microsoft.Win32.SaveFileDialog
                {
                    Filter = "Excel Files (*.xlsx)|*.xlsx",
                    DefaultExt = ".xlsx",
                    FileName = "Export"
                };

                if (dialog.ShowDialog() == true)
                {
                    // call export helper
                    _logger.Information($"Exporting to: {dialog.FileName}");
                }
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "btnExport_Click Exception");
                MessageBox.Show($"Export failed: {ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }

            _logger.Information($"Finished btnExport_Click()");
        }

        private void btnClose_Click(object sender, RoutedEventArgs e)
        {
            _logger.Information($"Starting btnClose_Click()");

            try
            {
                this.Close();
            }
            catch (Exception ex)
            {
                _logger.Error(ex, "btnClose_Click Exception");
            }

            _logger.Information($"Finished btnClose_Click()");
        }
    }
}
```

---

## Key WPF Rules for This Style

### 1. Code-Behind, Not MVVM

Use code-behind (`.xaml.cs`) for all event handling. No ViewModels, no `INotifyPropertyChanged`,
no data-binding to ViewModel properties. Keep it simple:

- Events → click handlers in code-behind
- Data → bind `DataTable.DefaultView` to `DataGrid.ItemsSource`
- No MVVM frameworks (Prism, MVVM Light, CommunityToolkit)

### 2. Constructor Injection (same as CommandFactory)

Pass `CommandFactory` and `Logger` into the Window constructor — never instantiate them inside the
Window. The script class (`Run()`) creates and passes them.

```csharp
// GOOD
public MainWindow(CommandFactory commandFactory, Logger logger)

// BAD — Window creates its own dependencies
public MainWindow()
{
    _commandFactory = new CommandFactory(...);
}
```

### 3. Every Event Handler Has Start/Finish Logging + Try/Catch

Same rule as all other methods:

```csharp
private void btnLoad_Click(object sender, RoutedEventArgs e)
{
    _logger.Information($"Starting btnLoad_Click()");
    try { ... }
    catch (Exception ex) { _logger.Error(ex, "btnLoad_Click Exception"); }
    _logger.Information($"Finished btnLoad_Click()");
}
```

### 4. MessageBox for User-Facing Errors

Use `System.Windows.MessageBox` (not `System.Windows.Forms.MessageBox`):

```csharp
MessageBox.Show("Message text", "Title", MessageBoxButton.OK, MessageBoxImage.Warning);
MessageBox.Show("Error text",   "Error", MessageBoxButton.OK, MessageBoxImage.Error);
MessageBox.Show("Info text",    "Info",  MessageBoxButton.OK, MessageBoxImage.Information);
```

### 5. WindowStartupLocation

Always set on the Window element:

```xml
WindowStartupLocation="CenterScreen"
```

### 6. DataGrid for Tabular Results

Prefer `DataGrid` for displaying `DataTable` results:

```csharp
dgResults.ItemsSource = myDataTable.DefaultView;
```

Use `AutoGenerateColumns="True"` for quick results. Define explicit columns only when specific
formatting or hiding is needed.

---

## File Dialog (WPF Style)

```csharp
// Open file
var openDialog = new Microsoft.Win32.OpenFileDialog
{
    Filter = "Excel Files (*.xlsx)|*.xlsx|All Files (*.*)|*.*",
    Multiselect = false
};
if (openDialog.ShowDialog() == true)
{
    string filePath = openDialog.FileName;
}

// Save file
var saveDialog = new Microsoft.Win32.SaveFileDialog
{
    Filter = "Excel Files (*.xlsx)|*.xlsx",
    DefaultExt = ".xlsx",
    FileName = "Output"
};
if (saveDialog.ShowDialog() == true)
{
    string savePath = saveDialog.FileName;
}
```

---

## Cursor / Busy State

```csharp
// Show busy cursor during long operations
this.Cursor = System.Windows.Input.Cursors.Wait;
try
{
    // long operation
}
finally
{
    this.Cursor = System.Windows.Input.Cursors.Arrow;
}
```

---

## What NOT to Do

```csharp
// NO — Windows Forms
public partial class MyForm : System.Windows.Forms.Form { }

// NO — MVVM ViewModel
public class MainViewModel : INotifyPropertyChanged { }

// NO — MVVM framework
// Prism, MVVM Light, CommunityToolkit.Mvvm — not used

// NO — creating dependencies inside Window
public MainWindow()
{
    _logger = ConfigurationHelper.CreateLogger();  // wrong — pass from outside
}

// NO — System.Windows.Forms.MessageBox in WPF project
System.Windows.Forms.MessageBox.Show("...");

// NO — missing try/catch in event handlers
private void btnLoad_Click(object sender, RoutedEventArgs e)
{
    dgResults.ItemsSource = _commandFactory.GetData().DefaultView;  // unguarded
}
```
