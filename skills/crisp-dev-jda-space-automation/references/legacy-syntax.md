# Legacy AutoPilot Script Syntax Reference

Documentation for the legacy JDA Space Automation (AutoPilot) scripting syntax used in v9.x and earlier.

---

## Line Prefixes (Modules)

Every command line must start with one of these prefixes:

| Prefix | Module | Purpose |
|---|---|---|
| `_GN_` | General | File I/O, variables, arrays, control flow, external apps |
| `_PS_` | Space Planning | Planogram, fixture, product, position operations |
| `_PF_` | Floor Planning | Floorplan, section, department operations |
| `_IKB_` | Intactix Knowledge Base | Category Knowledge Base / database operations |

- `_GN_'` = comment line (apostrophe right after prefix)
- A bare `_GN_` line = blank line separator

---

## Parameter Syntax

Parameters follow the command name in `{Key=Value}` pairs:
```
_PS_Open project file {FileName="C:\path\file.psa"}
_PS_Add planogram {Name="My POG"} {Height="72"} {Width="48"} {Depth="18"}
_GN_Create array {ArrayName="myArray"} {RowCount="10"} {ColumnCount="5"}
```

- String values may or may not use quotes
- `CurrentProject` = special keyword for the current file in a For Projects loop

---

## Variables

```
_GN_MyVar=Hello
_GN_MyVar=GetValue("Planogram","Width")
_PS_PlanogramHeight=GetValue("Planogram","Height")
```

All variables are untyped strings internally.

---

## Comments

```
_GN_' This is a comment
_GN_' Multiple comment lines look like this
```

---

## Control Flow

### If / Else If / Else / End if
```
_GN_If GetValue("Position","Capacity")=0 Then
  _PS_Delete position {Option="CurrentPosition"}
_GN_Else If GetValue("Position","Capacity")>10 Then
  _PS_Change horizontal facings {Facings=2}
_GN_Else
  _PS_Change horizontal facings {Facings=1}
_GN_End if
```

### Go To (with script labels)
```
_GN_:MyLabel
_GN_Go to {ScriptLabel=MyLabel}
```

### On Error
```
_GN_On error continue   ' Default: keep running despite errors
_GN_On error stop       ' Stop if any error occurs
```

### Pause / Message / Delay
```
_GN_Pause
_GN_Message box {MessageText="Done processing!"}
_GN_Set delay interval {Interval=500}
```

---

## Loops

### For Projects (batch processing)
```
_PS_Create file list {ListName="myFiles"} {UseSubdirectories="True"}
_PS_ C:\path\file1.psa
_PS_ C:\path\file2.psa
_PS_End create file list

_PS_Use file list {ListName="myFiles"}
_PS_For projects
  _PS_Open project file {FileName=CurrentProject}
  ' work here
  _PS_Save project file
  _PS_Close project file
_PS_End projects
```

### For Planograms / Floorplans
```
_PS_For planograms
  ' GetValue works in context of current planogram
_PS_End planograms

_PF_For floorplans
  _PF_Select floorplan {Name=GetValue("Floorplan","Name")}
_PF_End floorplans
```

### For Positions / Fixtures / Sections / Segments
```
_PS_For positions
  _GN_If GetValue("Position","Capacity")=0 Then
    _PS_Delete position {Option="CurrentPosition"}
  _GN_End if
_PS_End positions

_PS_For fixtures
_PS_End fixtures

_PF_For sections
_PF_End sections

_PS_For segments
_PS_End segments
```

### Nesting Loops
```
_PS_For projects
  _PS_Open project file {FileName=CurrentProject}
  _PS_For planograms
    _PS_For positions
      ' innermost: each position in each planogram in each project
    _PS_End positions
  _PS_End planograms
  _PS_Save project file
  _PS_Close project file
_PS_End projects
```

---

## Arrays

```
_GN_Create array {ArrayName="MyArr"} {RowCount="100"} {ColumnCount="3"}
_GN_Set array value {ArrayName="MyArr"} {Row="1"} {Column="1"} {Value="hello"}
_GN_Set specified array value {ArrayName="MyArr"} {Row="1"} {Column="Name"} {Value="hello"}

_GN_For array rows {ArrayName="MyArr"}
  ' GetArrayValue("MyArr","ColumnName") gets current row value
_GN_End array rows

_GN_Delete array {ArrayName="MyArr"}
_GN_Convert array to list {ArrayName="MyArr"} {ListName="myList"}
_GN_Read delimited file into array {FileName="data.csv"} {ArrayName="DataArr"} {Delimiter=","}
_GN_Read delimited string into array {String=MyVar} {ArrayName="SArr"} {Delimiter=","}
```

---

## File I/O

### Output File
```
_GN_Open output file {FileName="C:\output\report.txt"}
_GN_Write to file {Text="Header"}
_PS_For positions
  _GN_Write to file {Text=GetValue("Position","UPC")}
_PS_End positions
_GN_Close output file
```

### Input File
```
_GN_Open input file {FileName="C:\input\data.txt"}
_GN_For input file
  _GN_MyLine=GetInputLine()
_GN_End for input file
_GN_Close input file
```

---

## Functions

| Function | Description |
|---|---|
| `GetValue("ObjectType","FieldName")` | Get a field value from current object |
| `GetInputLine()` | Get current line from open input file |
| `GetArrayValue("ArrayName","Column")` | Get value from current array row |
| `PromptUserForFile("prompt","filter")` | Show file open dialog, returns path |
| `DeriveFileName(source,"*.ext","dir")` | Build a new file path from source |
| `Left(str, n)` | Left n characters |
| `Right(str, n)` | Right n characters |
| `Mid(str, start, len)` | Substring |
| `Contains(str, substr)` | True/False |

---

## Space Planning Commands (Selected)

```
_PS_Create new project
_PS_Open project file {FileName="path.psa"}
_PS_Save project file
_PS_Close project file
_PS_Save project version {VersionName="v1"}

_PS_Add planogram {Name="POG"} {Height="72"} {Width="48"} {Depth="18"} {BaseHeight="4"} {BaseWidth="48"} {BaseDepth="18"}
_PS_Select planogram {Name="POG"} {RemoveSelection="Yes"}
_PS_Delete planogram
_PS_Redraw off
_PS_Redraw on
_PS_Hide application
_PS_Show application

_PS_Add product from product library {UPC="123456"}
_PS_Delete products {Option="UnusedProducts"}
_PS_Set product field {ProductKey=GetValue("Product","ProductKey")} {Field="Color"} {NewValue="RED"}
_PS_Set position field {ProductKey=GetValue("Position","ProductKey")} {Field="Capacity"} {NewValue="10"}
_PS_Change horizontal facings {Facings=2}
_PS_Increase horizontal facings
_PS_Decrease vertical facings
_PS_Delete position {Option="CurrentPosition"}

_PS_Open product library {LibraryName="lib.psp"}
_PS_Close product library
_PS_Update product library from project
_PS_Update project from product library
_PS_Open planogram library {LibraryName="lib.pfp"}
_PS_Close planogram library

_PS_Open table/chart view {TableFile="table.pst"}
_PS_Export table {FileName="out.html"}
_PS_Close table/chart view
_PS_Export image {LayoutFile="layout.psy"} {Page="1"} {ImageType="JPEG (*.jpg)"} {File="out.jpg"} {Resolution="150"}
_PS_Print using layout {LayoutFile="layout.psy"}
_PS_Export 3ds {3DS filename="out.3ds"} {External Compatibility="True"}
```

---

## Floor Planning Commands (Selected)

```
_PF_Create new project
_PF_Open project file {FileName="path.pfa"}
_PF_Save project file
_PF_Close project file

_PF_Add floorplan {Name="Store"} {Width="1440"} {Depth="1440"} {CeilingHeight="192"}
_PF_Select floorplan {Name="Store"}
_PF_Delete floorplan {Name="Store"}
_PF_For sections
_PF_End sections
_PF_Explode section {SectionCount=2}
_PF_Split fixture
_PF_Join fixtures
_PF_Move section

_PF_Export image {LayoutFile="[CurrentView]"} {Page="1"} {ImageType="JPEG (*.jpg)"} {File="out.jpg"}
_PF_Print using layout {LayoutFile="layout.pfy"}
```

---

## Unsupported Commands (No SA Pro Equivalent)

These are flagged with `###` during automated conversion:
- `Add planogram to scorecard`
- `Create filter` / `End create filter`
- `Close floorplan window`
- `Open floorplan file` (legacy InterCept)
- `Print Intersection report`
- `Run Intercept macro`
