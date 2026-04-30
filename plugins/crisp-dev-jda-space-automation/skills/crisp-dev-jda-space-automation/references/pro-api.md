# SA Pro C# API Reference

SA Pro scripts are written in C# (or VB.NET) and run inside the SA Pro scripting engine.

Full HTML reference: the SA Pro help file ships with the SA Pro installation. Look for `SA Pro.htm` inside your SA Pro install directory or the `SA Help Files\` folder in your automation repo.

---

## Two Scripting Styles

### Classic Style
Call methods on the global `SpacePlanning` / `FloorPlanning` singletons:
```csharp
SpacePlanning.OpenProjectFile(@"C:\path\project.psa");
SpacePlanning.SaveProjectFile();
SpacePlanning.CloseProjectFile();
```

### Instance Style
Get a typed object reference and call methods on it:
```csharp
SpacePlanning.OpenProjectFile(@"C:\path\project.psa");
Space.Project proj = SpacePlanning.ActiveProject;
Space.Planogram pog = SpacePlanning.ActivePlanogram;
// pog.SomeMethod(...)
```

Both are valid; instance style is preferred when operating on a specific object.

---

## Key Types

| Type | Description |
|---|---|
| `Space.Project` | A Space Planning project (.psa file) |
| `Space.Planogram` | A planogram within a project |
| `Space.Fixture` | A fixture on a planogram |
| `Space.Position` | A product position on a fixture |
| `Space.Product` | A product definition |
| `Space.Segment` | A planogram segment |
| `Floor.Project` | A Floor Planning project (.pfa file) |
| `Floor.Floorplan` | A floorplan within a project |
| `Floor.Section` | A section within a floorplan |
| `Floor.Department` | A department on a floorplan |

---

## Project / File Operations

```csharp
SpacePlanning.CreateNewProject();
Space.Project proj = SpacePlanning.OpenProjectFile(@"C:\path\file.psa");
SpacePlanning.SaveProjectFile();
SpacePlanning.CloseProjectFile();
SpacePlanning.SaveProjectVersion("VersionName");

FloorPlanning.CreateNewProject();
Floor.Project flrProj = FloorPlanning.OpenProjectFile(@"C:\path\file.pfa");
FloorPlanning.SaveProjectFile();
FloorPlanning.CloseProjectFile();
```

---

## Iterating / Batch Processing

### ForProjects — by directory
```csharp
foreach (Space.Project proj in SpacePlanning.ForProjects(
    sourceDirectory: @"C:\Planograms",
    fileExtension: "psa",
    useSubDirectories: false))
{
    // project is automatically opened
    SpacePlanning.SaveProjectFile();
    SpacePlanning.CloseProjectFile();
}
```

### ForProjects — by explicit file list
```csharp
foreach (Space.Project proj in SpacePlanning.ForProjects(
    new string[] { @"C:\path\a.psa", @"C:\path\b.psa" }))
{
    SpacePlanning.CloseProjectFile();
}
```

### ForPlanograms / ForFloorplans
```csharp
foreach (Space.Planogram pog in SpacePlanning.ForPlanograms())
{
    // pog is active; also SpacePlanning.ActivePlanogram
}

foreach (Floor.Floorplan flr in FloorPlanning.ForFloorplans())
{
    // flr is the active floorplan
}
```

### ForPositions / ForFixtures / ForSections
```csharp
foreach (Space.Position pos in SpacePlanning.ForPositions())
{
    // pos.Capacity, pos.UPC, pos.Name, etc.
}

foreach (Space.Fixture fix in SpacePlanning.ForFixtures())
{
    // fix.Name, fix.Width, fix.Height, etc.
}

foreach (Floor.Section sec in FloorPlanning.ForSections())
{
    // sec.Name, sec.PlanogramKey, etc.
}
```

### Conditional WHERE filtering
```csharp
foreach (Space.Position pos in SpacePlanning.ForPositions(whereCondition: "Capacity = 0"))
{
    SpacePlanning.DeletePosition();
}
```

---

## Adding Objects

```csharp
SpacePlanning.AddPlanogram("POGName", height: 72.0, width: 48.0, depth: 18.0,
    baseHeight: 4.0, baseWidth: 48.0, baseDepth: 18.0);

FloorPlanning.AddFloorplan("StoreName", width: 1440.0, depth: 1440.0, ceilingHeight: 192.0);

SpacePlanning.AddFixture("ShelfName", SpaceFixtureTypes.Shelf,
    height: 1.0, width: 48.0, depth: 18.0, x: 0, y: 0, z: 0);

SpacePlanning.AddDrawing("MyDrawing", DrawingType.Rectangle,
    height: 30, width: 30, depth: 30, x: 10, y: 10, z: 10);

FloorPlanning.AddFixture("Gondola1", width: 48.0, depth: 18.0, x: 100, y: 100, angle: 0);

SpacePlanning.AddProductFromProductLibrary(upc: "12345678");
SpacePlanning.AddPlanogramFromPlanogramLibrary(libraryPlanogramKey: "key");
```

---

## Deleting Objects

```csharp
SpacePlanning.DeletePosition();  // inside ForPositions loop
SpacePlanning.DeletePlanogram("PlanogramName");
SpacePlanning.DeletePlanogramsWithCondition(condition: "Width < 24");
SpacePlanning.DeletePositionsWithCondition(condition: "Capacity = 0");
SpacePlanning.DeleteFixturesWithCondition(condition: "Type = 'Peg'");
SpacePlanning.DeleteProducts(DeleteProductsOption.UnusedProducts);
```

---

## Field Values

### Direct Property Access (Preferred)

**Always use direct property access instead of GetFieldValue() / SetFieldValue().**

All JDA objects expose fields as properties. This is cleaner, type-safe, and more idiomatic.

#### Reading Field Values

**BAD:**
```csharp
var desc1 = pog.GetFieldValue("Desc 1").Trim();
var desc3 = pog.GetFieldValue("Desc 3").Trim();
var dateEffective = pog.GetFieldValue("Date Effective");
```

**GOOD:**
```csharp
var desc1 = pog.Desc1.Trim();
var desc3 = pog.Desc3.Trim();
var dateEffective = pog.DateEffective;
```

#### Common Field Properties

**Planogram Fields:**
```csharp
var pog = SpacePlanning.ActivePlanogram;
var name = pog.Name;
var desc1 = pog.Desc1;      // Desc1 through Desc50
var desc2 = pog.Desc2;
var dateEffective = pog.DateEffective;  // Double (OLE date)
var dateCreated = pog.DateCreated;      // Double
var dateModified = pog.DateModified;    // Double
```

**Floorplan Fields:**
```csharp
var flr = FloorPlanning.ActiveFloorplan;
var name = flr.Name;
var desc1 = flr.Desc1;      // Desc1 through Desc50
var desc3 = flr.Desc3;
var dateLive = flr.DateLive;        // Double (OLE date)
var dateCreated = flr.DateCreated;  // Double
```

**Position Fields:**
```csharp
var pos = SpacePlanning.ActivePosition;
var productKey = pos.ProductKey;
var capacity = pos.Capacity;
var upc = pos.UPC;
```

**Fixture Fields:**
```csharp
var fix = SpacePlanning.ActiveFixture;
var name = fix.Name;
var width = fix.Width;
var height = fix.Height;
```

#### Field Defaults

JDA API guarantees default values — no null checks needed:
- **Description fields** (`Desc1`, `Desc2`, `Name`, etc.) → Empty string by default
- **Date/numeric fields** (`DateEffective`, `DateLive`, `Capacity`, etc.) → `0` by default

```csharp
// No null-coalescing needed
var desc1 = pog.Desc1.Trim();  // Returns empty string if unset

// Validate dates with == 0 check
if (pog.DateEffective == 0)
{
    _logger.Warning("DateEffective is not set");
}
```

#### Date Conversion

Date fields return `Double` (OLE Automation date). Use `DateTime.FromOADate()`:

```csharp
var dateEffective = pog.DateEffective;

if (dateEffective != 0)
{
    var formattedDate = DateTime.FromOADate(dateEffective).ToString("M/d/yyyy");
    var year = DateTime.FromOADate(dateEffective).Year;
}
```

### Setting Field Values (Legacy Methods)

While reading should use properties, setting still uses methods:

```csharp
SpacePlanning.SetPlanogramField("PlanogramName", "FieldName", "NewValue");
SpacePlanning.SetFixtureField(fix.FixtureKey, "Color", "BLUE");
SpacePlanning.SetPositionField(pos.ProductKey, "Capacity", "10");
SpacePlanning.SetProductField(prod.ProductKey, "Color", "RED");
FloorPlanning.SetFloorplanField("FloorplanName", "Description", "Updated");
FloorPlanning.SetSectionField(sec.PlanogramKey, "Description", "New Desc");
SpacePlanning.SetFieldValue("Planogram", "PlanogramName", "Description", "My desc");
```

---

## Visual / Performance Settings

```csharp
SpacePlanning.RedrawOff();    // stop redrawing — speeds up bulk ops
SpacePlanning.RedrawOn();
```

> `HideApplication()` / `ShowApplication()` are not used in SA Pro. Do not emit these calls
> when converting legacy `_PS_Hide application` / `_PS_Show application` commands — omit them.

---

## Facings

```csharp
SpacePlanning.ChangeHorizontalFacings(facings: 2);
SpacePlanning.ChangeVerticalFacings(facings: 3);
SpacePlanning.IncreaseHorizontalFacings();
SpacePlanning.DecreaseHorizontalFacings();
SpacePlanning.IncreaseVerticalFacings();
SpacePlanning.DecreaseVerticalFacings();
```

---

## Library Operations

```csharp
SpacePlanning.OpenProductLibrary(@"C:\Libraries\Products.psp");
SpacePlanning.CloseProductLibrary();
SpacePlanning.UpdateProductLibraryFromProject();
SpacePlanning.UpdateProjectFromProductLibrary();

SpacePlanning.OpenPlanogramLibrary(@"C:\Libraries\Planograms.pfp");
SpacePlanning.ClosePlanogramLibrary();
SpacePlanning.UpdatePlanogramLibraryFromProject();
SpacePlanning.UpdateProjectFromPlanogramLibrary();

SpacePlanning.OpenFixtureLibrary(@"C:\Libraries\Fixtures.psf");
SpacePlanning.CloseFixtureLibrary();

FloorPlanning.OpenFixtureLibrary(@"C:\Libraries\FPFixtures.pff");
FloorPlanning.CloseFixtureLibrary();
```

---

## Export / Print

```csharp
SpacePlanning.ExportImage(@"C:\output\planogram.jpg", ExportMethod.JPEG, width: 1920, height: 1080);
FloorPlanning.ExportImage(@"C:\output\floorplan.jpg", ExportMethod.JPEG, width: 1920, height: 1080);

SpacePlanning.Export3DS(@"C:\output\model.3ds");
SpacePlanning.ExportFBX(@"C:\output\model.fbx");

SpacePlanning.OpenTableChartView(@"C:\tables\ShelfReport.pst");
SpacePlanning.ExportTableData(@"C:\output\report.html");
SpacePlanning.ExportExcelTableData(@"C:\output\report.xlsx");
SpacePlanning.CloseTableChartView();

SpacePlanning.PrintUsingLayout(@"C:\layouts\Standard.psy");
FloorPlanning.PrintUsingLayout(@"C:\layouts\Standard.pfy");

SpacePlanning.CreatePrintList(@"C:\printlist.psi");
SpacePlanning.AddEntryToPrintList(
    printList: @"C:\printlist.psi",
    projectFile: @"C:\project.psa",
    layoutFile: SpaceLayoutFile.SeeConfiguration,
    planogram: "12' Coffee Makers");
SpacePlanning.PrintUsingPrintList(@"C:\printlist.psi");
```

---

## Validation Patterns

### Object Null Checks

Always validate that JDA objects are not null after retrieval:

```csharp
var pog = SpacePlanning.ActivePlanogram;

if (pog == null)
{
    _logger.Warning($"Planogram DBKey {myKey} is null after opening");
    continue;
}
```

### Required Field Validation

Validate required fields before using them:

```csharp
// String fields - check for null or whitespace
if (string.IsNullOrWhiteSpace(pog.Name))
{
    _logger.Warning($"Planogram DBKey {myKey} has null or empty Name");
    SpacePlanning.CloseProjectFile();
    continue;
}

if (string.IsNullOrWhiteSpace(desc1) || string.IsNullOrWhiteSpace(desc3))
{
    _logger.Warning($"Planogram DBKey {myKey} has invalid descriptors");
    SpacePlanning.CloseProjectFile();
    continue;
}

// Date fields - check for 0 (unset)
if (pog.DateEffective == 0)
{
    _logger.Warning($"Planogram DBKey {myKey} has invalid DateEffective");
    SpacePlanning.CloseProjectFile();
    continue;
}
```

### Directory Validation

Always validate directories exist before file operations:

```csharp
if (!Directory.Exists(archivePath))
{
    _logger.Warning($"Archive path does not exist: {archivePath}");
    Directory.CreateDirectory(archivePath);
    _logger.Information($"Created archive path: {archivePath}");
}

var targetDirectory = Path.Combine(archivePath, desc1, desc3, desc5);

if (!Directory.Exists(targetDirectory))
{
    Directory.CreateDirectory(targetDirectory);
}
```

### Complete Validation Example

```csharp
foreach (DataRow row in keysTable.Rows)
{
    var myKey = row[0].ToString();

    try
    {
        SpacePlanning.OpenPlanogramFromDatabase(myKey);

        var pog = SpacePlanning.ActivePlanogram;

        if (pog == null)
        {
            logger.Warning($"Planogram DBKey {myKey} is null after opening");
            continue;
        }

        var desc1 = pog.Desc1.Trim();
        var desc3 = pog.Desc3.Trim();
        var dateEffective = pog.DateEffective;

        if (string.IsNullOrWhiteSpace(pog.Name))
        {
            logger.Warning($"Planogram DBKey {myKey} has null or empty Name");
            SpacePlanning.CloseProjectFile();
            continue;
        }

        if (string.IsNullOrWhiteSpace(desc1) || string.IsNullOrWhiteSpace(desc3))
        {
            logger.Warning($"Planogram DBKey {myKey} has invalid descriptors");
            SpacePlanning.CloseProjectFile();
            continue;
        }

        if (dateEffective == 0)
        {
            logger.Warning($"Planogram DBKey {myKey} has invalid DateEffective");
            SpacePlanning.CloseProjectFile();
            continue;
        }

        if (!Directory.Exists(archivePath))
        {
            Directory.CreateDirectory(archivePath);
        }

        // Process planogram...

        SpacePlanning.CloseProjectFile();
        logger.Information($"Processed planogram DBKey {myKey}");
    }
    catch (Exception ex)
    {
        logger.Error(ex, $"Error processing planogram DBKey {myKey}");
        try { SpacePlanning.CloseProjectFile(); } catch { }
    }
}
```

---

## Database Operations

```csharp
SpacePlanning.SelectDatabase(databaseName: "MyDB", serverName: "(local)", userName: "user1");
FloorPlanning.SelectDatabase("MyDB", "(local)", "user1");

foreach (Space.Project proj in SpacePlanning.ForDatabaseProjects(whereCondition: "..."))
{
    // proj from database
}

var results = SpacePlanning.ExecuteQuery("SELECT * FROM Products WHERE Color = 'RED'");
```

---

## File System (Standard C#)

```csharp
using System.IO;
using System.Diagnostics;

// Write a report
using (var writer = new StreamWriter(@"C:\output\report.txt"))
{
    writer.WriteLine("Report Header");
    foreach (Space.Position pos in SpacePlanning.ForPositions())
    {
        writer.WriteLine(pos.UPC);
    }
}

// Read a CSV file
foreach (string line in File.ReadLines(@"C:\input\data.txt"))
{
    string[] parts = line.Split(',');
    // process parts
}

File.Copy(@"C:\src\file.psa", @"C:\dst\file.psa");
File.Move(@"C:\src\file.psa", @"C:\dst\file.psa");
File.Delete(@"C:\old\file.psa");
Directory.CreateDirectory(@"C:\new\folder");
Directory.Delete(@"C:\old\folder", recursive: true);
Process.Start(@"C:\tools\myapp.exe");
```

---

## Error Handling

```csharp
// Equivalent of "On Error Continue"
try
{
    SpacePlanning.OpenProjectFile(@"C:\file.psa");
    // ... operations ...
}
catch (Exception ex)
{
    Console.WriteLine($"Error: {ex.Message}");
    // continue to next item
}

// "On Error Stop" = just don't use try/catch; let exceptions propagate naturally
```

---

## Full Example: Batch Export Planogram Images

```csharp
// Export JPEG for each planogram in each project

foreach (Space.Project proj in SpacePlanning.ForProjects(
    sourceDirectory: @"C:\Planograms",
    fileExtension: "psa",
    useSubDirectories: false))
{
    foreach (Space.Planogram pog in SpacePlanning.ForPlanograms())
    {
        string safeName = pog.Name.Replace(" ", "_").Replace("'", "");
        string outputPath = $@"C:\output\{safeName}.jpg";
        SpacePlanning.ExportImage(outputPath, ExportMethod.JPEG, width: 1600, height: 900);
    }
    SpacePlanning.CloseProjectFile();
}
```
