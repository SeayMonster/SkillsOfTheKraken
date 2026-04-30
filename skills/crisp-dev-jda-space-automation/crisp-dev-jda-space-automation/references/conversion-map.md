# Legacy AutoPilot -> SA Pro C# Conversion Map

Primary reference for converting legacy scripts to SA Pro C#. Find the legacy command on the left, use the SA Pro equivalent on the right.

---

## Project / File Operations

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_PS_Open project file {FileName="path.psa"}` | `SpacePlanning.OpenProjectFile(@"path.psa");` |
| `_PF_Open project file {FileName="path.pfa"}` | `FloorPlanning.OpenProjectFile(@"path.pfa");` |
| `_PS_Close project file` | `SpacePlanning.CloseProjectFile();` |
| `_PF_Close project file` | `FloorPlanning.CloseProjectFile();` |
| `_PS_Save project file` | `SpacePlanning.SaveProjectFile();` |
| `_PF_Save project file` | `FloorPlanning.SaveProjectFile();` |
| `_PS_Create new project` | `SpacePlanning.CreateNewProject();` |
| `_PF_Create new project` | `FloorPlanning.CreateNewProject();` |
| `_PS_Save project version {VersionName=v1}` | `SpacePlanning.SaveProjectVersion("v1");` |

---

## File Lists -> ForProjects()

The legacy Create/Use File List + For Projects pattern maps to `ForProjects()` in SA Pro.

**Legacy:**
```
_PS_Create file list {ListName="mylist"} {UseSubdirectories="False"}
_PS_ C:\Planograms\project1.psa
_PS_ C:\Planograms\project2.psa
_PS_End create file list
_PS_Use file list {ListName="mylist"}
_PS_For projects
  _PS_Open project file {FileName=CurrentProject}
  ' ... work ...
  _PS_Save project file
  _PS_Close project file
_PS_End projects
```

**SA Pro C# (explicit file list):**
```csharp
foreach (Space.Project proj in SpacePlanning.ForProjects(
    new string[] { @"C:\Planograms\project1.psa", @"C:\Planograms\project2.psa" }))
{
    // project is auto-opened
    SpacePlanning.SaveProjectFile();
    SpacePlanning.CloseProjectFile();
}
```

**SA Pro C# (entire directory):**
```csharp
foreach (Space.Project proj in SpacePlanning.ForProjects(
    sourceDirectory: @"C:\Planograms",
    fileExtension: "psa",
    useSubDirectories: false))
{
    SpacePlanning.SaveProjectFile();
    SpacePlanning.CloseProjectFile();
}
```

---

## Loop Commands

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_PS_For projects ... End projects` | `foreach (Space.Project p in SpacePlanning.ForProjects(...))` |
| `_PF_For projects ... End projects` | `foreach (Floor.Project p in FloorPlanning.ForProjects(...))` |
| `_PS_For planograms ... End planograms` | `foreach (Space.Planogram pog in SpacePlanning.ForPlanograms())` |
| `_PF_For floorplans ... End floorplans` | `foreach (Floor.Floorplan flr in FloorPlanning.ForFloorplans())` |
| `_PS_For positions ... End positions` | `foreach (Space.Position pos in SpacePlanning.ForPositions())` |
| `_PS_For fixtures ... End fixtures` | `foreach (Space.Fixture fix in SpacePlanning.ForFixtures())` |
| `_PF_For sections ... End sections` | `foreach (Floor.Section sec in FloorPlanning.ForSections())` |
| `_PS_For segments ... End segments` | `foreach (Space.Segment seg in SpacePlanning.ForSegments())` |
| `_GN_For input file ... End for input file` | `foreach (string line in File.ReadLines(@"path.txt"))` |
| `_GN_For array rows {ArrayName=arr}` | `foreach (var row in myList)` or standard `for` loop |

---

## Conditional & Control Flow

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_GN_If condition Then ... _GN_End if` | `if (condition) { ... }` |
| `_GN_Else if condition Then` | `else if (condition) { ... }` |
| `_GN_Else` | `else { ... }` |
| `_GN_On error continue` | `try { } catch { /* log and continue */ }` |
| `_GN_On error stop` | Let exceptions propagate (default C# behavior) |
| `_GN_Go to {ScriptLabel=label}` | Restructure with `break`, `continue`, or helper methods |
| `_GN_Message box {MessageText="msg"}` | `Console.WriteLine("msg");` |
| `_GN_Set delay interval {Interval=n}` | `System.Threading.Thread.Sleep(n);` |
| `_GN_Pause` | `Console.ReadLine();` or omit for unattended scripts |

---

## Variables & Data

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_GN_VarName=value` | `string varName = "value";` |
| `_GN_VarName=GetValue("Type","Field")` | `string varName = item.GetFieldValue("Field");` |
| String concat `"a" & "b"` | `"a" + "b"` or `$"a{b}"` |
| `_GN_Create array {ArrayName=arr} {RowCount=10}` | `var list = new List<string>();` |
| `_GN_Set array value ... {Value=x}` | `list.Add(x);` or `arr[i] = x;` |
| `_GN_Read delimited file into array {FileName=f} {Delimiter=,}` | `var lines = File.ReadAllLines(f);` then split |

---

## GetValue -> SA Pro Object Properties

`GetValue("ObjectType","FieldName")` in legacy maps to typed properties in SA Pro:

| Legacy | SA Pro C# (instance) |
|---|---|
| `GetValue("Planogram","Width")` | `pog.Width` or `pog.GetFieldValue("Width")` |
| `GetValue("Planogram","Height")` | `pog.Height` |
| `GetValue("Position","Capacity")` | `pos.Capacity` |
| `GetValue("Position","UPC")` | `pos.UPC` |
| `GetValue("Position","ProductKey")` | `pos.ProductKey` |
| `GetValue("Fixture","Name")` | `fix.Name` |
| `GetValue("Fixture","FixtureKey")` | `fix.FixtureKey` |
| `GetValue("Floorplan","Name")` | `flr.Name` |
| `GetValue("Section","PlanogramKey")` | `sec.PlanogramKey` |
| `GetValue("Product","Target Inventory")` | `product.GetFieldValue("Target Inventory")` |

---

## Set Field Commands

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_PS_Set planogram field {Name=p} {Field=f} {NewValue=v}` | `SpacePlanning.SetPlanogramField("p", "f", "v");` |
| `_PS_Set fixture field {FixtureKey=k} {Field=f} {NewValue=v}` | `SpacePlanning.SetFixtureField(k, "f", "v");` |
| `_PS_Set position field {ProductKey=k} {Field=f} {NewValue=v}` | `SpacePlanning.SetPositionField(k, "f", "v");` |
| `_PS_Set product field {ProductKey=k} {Field=f} {NewValue=v}` | `SpacePlanning.SetProductField(k, "f", "v");` |
| `_PF_Set floorplan field {Name=f} {Field=x} {NewValue=v}` | `FloorPlanning.SetFloorplanField("f", "x", "v");` |
| `_PF_Set section field {PlanogramKey=k} {Field=x} {NewValue=v}` | `FloorPlanning.SetSectionField(k, "x", "v");` |

---

## Visual / Performance

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_PS_Redraw off` | `SpacePlanning.RedrawOff();` |
| `_PS_Redraw on` | `SpacePlanning.RedrawOn();` |
| `_PS_Hide application` | *(omit — not needed in SA Pro)* |
| `_PS_Show application` | *(omit — not needed in SA Pro)* |
| `_PF_Hide application` | *(omit — not needed in SA Pro)* |
| `_PF_Show application` | *(omit — not needed in SA Pro)* |

---

## Facings

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_PS_Change horizontal facings {Facings=n}` | `SpacePlanning.ChangeHorizontalFacings(n);` |
| `_PS_Change vertical facings {Facings=n}` | `SpacePlanning.ChangeVerticalFacings(n);` |
| `_PS_Increase horizontal facings` | `SpacePlanning.IncreaseHorizontalFacings();` |
| `_PS_Decrease horizontal facings` | `SpacePlanning.DecreaseHorizontalFacings();` |
| `_PS_Increase vertical facings` | `SpacePlanning.IncreaseVerticalFacings();` |
| `_PS_Decrease vertical facings` | `SpacePlanning.DecreaseVerticalFacings();` |

---

## Planogram / Floorplan Management

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_PS_Add planogram {Name=n} {Height=h} {Width=w} {Depth=d} ...` | `SpacePlanning.AddPlanogram("n", h, w, d, bh, bw, bd);` |
| `_PS_Select planogram {Name=n}` | `SpacePlanning.SelectPlanogram("n");` |
| `_PS_Delete planogram` | `SpacePlanning.DeletePlanogram("name");` |
| `_PS_Delete planograms {Option=UnusedPlanograms}` | `SpacePlanning.DeletePlanograms(DeletePlanogramsOption.UnusedPlanograms);` |
| `_PF_Add floorplan {Name=n} {Width=w} {Depth=d} {CeilingHeight=ch}` | `FloorPlanning.AddFloorplan("n", w, d, ch);` |
| `_PF_Select floorplan {Name=n}` | `FloorPlanning.SelectFloorplan("n");` |

---

## Libraries

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_PS_Open product library {LibraryName="path.psp"}` | `SpacePlanning.OpenProductLibrary(@"path.psp");` |
| `_PS_Close product library` | `SpacePlanning.CloseProductLibrary();` |
| `_PS_Update product library from project` | `SpacePlanning.UpdateProductLibraryFromProject();` |
| `_PS_Update project from product library` | `SpacePlanning.UpdateProjectFromProductLibrary();` |
| `_PS_Open planogram library {LibraryName="path.pfp"}` | `SpacePlanning.OpenPlanogramLibrary(@"path.pfp");` |
| `_PS_Close planogram library` | `SpacePlanning.ClosePlanogramLibrary();` |
| `_PS_Update planogram library from project` | `SpacePlanning.UpdatePlanogramLibraryFromProject();` |
| `_PS_Update project from planogram library` | `SpacePlanning.UpdateProjectFromPlanogramLibrary();` |
| `_PS_Open fixture library {LibraryName="path.psf"}` | `SpacePlanning.OpenFixtureLibrary(@"path.psf");` |
| `_PF_Open fixture library {LibraryName="path.pff"}` | `FloorPlanning.OpenFixtureLibrary(@"path.pff");` |

---

## Export & Print

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_PS_Export image {ImageType="JPEG (*.jpg)"} {File="out.jpg"}` | `SpacePlanning.ExportImage(@"out.jpg", ExportMethod.JPEG, width, height);` |
| `_PF_Export image {LayoutFile="[CurrentView]"} {File="out.jpg"}` | `FloorPlanning.ExportImage(@"out.jpg", ExportMethod.JPEG, width, height);` |
| `_PS_Open table/chart view {TableFile="path.pst"}` | `SpacePlanning.OpenTableChartView(@"path.pst");` |
| `_PS_Export table {FileName="out.html"}` | `SpacePlanning.ExportTableData(@"out.html");` |
| `_PS_Close table/chart view` | `SpacePlanning.CloseTableChartView();` |
| `_PS_Print using layout {LayoutFile="path.psy"}` | `SpacePlanning.PrintUsingLayout(@"path.psy");` |
| `_PF_Print using layout {LayoutFile="path.pfy"}` | `FloorPlanning.PrintUsingLayout(@"path.pfy");` |
| `_PS_Export 3ds {3DS filename="out.3ds"}` | `SpacePlanning.Export3DS(@"out.3ds");` |

---

## File System (Standard C#)

| Legacy AutoPilot | SA Pro C# |
|---|---|
| `_GN_Open output file {FileName="out.txt"}` | `var writer = new StreamWriter(@"out.txt");` |
| `_GN_Write to file {Text="line"}` | `writer.WriteLine("line");` |
| `_GN_Close output file` | `writer.Close();` (prefer `using` block) |
| `_GN_Open input file {FileName="in.txt"}` | `var reader = new StreamReader(@"in.txt");` |
| `_GN_Copy file {FileToCopy=src} {NewFileLocation=dst}` | `File.Copy(src, dst);` |
| `_GN_Move file {FileToMove=src} {NewFileLocation=dst}` | `File.Move(src, dst);` |
| `_GN_Delete file {FileName=f}` | `File.Delete(f);` |
| `_GN_Create new directory {DirectoryName=d}` | `Directory.CreateDirectory(d);` |
| `_GN_Delete directory {DirectoryName=d}` | `Directory.Delete(d, recursive: true);` |
| `_GN_Run external application {Application="app.exe"}` | `Process.Start(@"app.exe");` |

---

## Complete Conversion Example

### Legacy AutoPilot Script
```
_GN_' Loop positions, delete zero-capacity ones, log UPCs to file
_GN_Open output file {FileName="C:\Reports\removed.txt"}
_GN_Write to file {Text="Removed Products"}
_PS_Open project file {FileName="C:\Planograms\Coffee.psa"}
_PS_For planograms
  _PS_For positions
    _GN_If GetValue("Position","Capacity")=0 Then
      _GN_Write to file {Text=GetValue("Position","UPC")}
      _PS_Delete position {Option="CurrentPosition"}
    _GN_End if
  _PS_End positions
_PS_End planograms
_PS_Save project file
_PS_Close project file
_GN_Close output file
```

### SA Pro C# Equivalent
```csharp
// Loop positions, delete zero-capacity ones, log UPCs to file
using (var writer = new System.IO.StreamWriter(@"C:\Reports\removed.txt"))
{
    writer.WriteLine("Removed Products");

    SpacePlanning.OpenProjectFile(@"C:\Planograms\Coffee.psa");

    foreach (Space.Planogram pog in SpacePlanning.ForPlanograms())
    {
        foreach (Space.Position pos in SpacePlanning.ForPositions())
        {
            if (pos.Capacity == 0)
            {
                writer.WriteLine(pos.UPC);
                SpacePlanning.DeletePosition();
            }
        }
    }

    SpacePlanning.SaveProjectFile();
    SpacePlanning.CloseProjectFile();
}
```
