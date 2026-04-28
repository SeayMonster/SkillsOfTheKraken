---
name: crisp-dev-jda-space-automation
description: >
  Convert, write, explain, and debug JDA Space Automation scripts — both legacy AutoPilot (.sas)
  scripts and modern SA Pro C# scripts. Use this skill whenever the user is working with JDA
  Space Automation, AutoPilot scripting, Space Planning (.psa), Floor Planning (.pfa), or SA Pro
  automation. This includes converting legacy _PS_/_PF_/_GN_ prefix scripts into C# SA Pro code,
  writing new Pro scripts from scratch, explaining what a script does, or debugging syntax errors
  in either format. Trigger any time the user pastes or references an AutoPilot script, asks about
  SA commands, mentions planogram automation, or wants C# equivalents for legacy Space Automation.
---

# JDA Space Automation Skill

You help users convert, write, debug, and understand JDA Space Automation scripts. There are two
distinct scripting systems in play:

- **Legacy (AutoPilot / Classic)** — line-based scripts with `_GN_`/`_PS_`/`_PF_` command
  prefixes and `{Parameter=Value}` syntax, used in Space Automation 9.x and earlier.
- **SA Pro (Professional)** — C# code using the `SpacePlanning.*` and `FloorPlanning.*` object
  model, the modern SA Pro scripting engine.

The **primary goal** of this project is converting legacy AutoPilot scripts to SA Pro C#.

## Reference Files

Read these before performing complex tasks:

- **`references/project-structure.md`** — How to scaffold a new SA Pro script project: folder
  layout, .csproj settings, registry-based JDA references, MSBuild targets, App.Config format,
  namespace/class naming rules. **Read this first when creating or scaffolding a project.**
- **`references/conversion-map.md`** — Side-by-side command mapping: legacy → SA Pro C#.
  **Read this first for any conversion task.**
- **`references/legacy-syntax.md`** — Full legacy AutoPilot syntax reference (prefixes, loops,
  functions, parameters). Read when the user provides legacy scripts or asks about legacy syntax.
- **`references/pro-api.md`** — SA Pro C# API reference (method signatures, examples).
  Read when writing or converting to SA Pro C# code.

## Non-Negotiable Rules

### One Script = One Project
**Every converted script must be its own standalone Visual Studio project.**
Never place multiple converted scripts in a single shared project.

- Follow the folder structure in `references/project-structure.md` exactly.
- Use `OutputType=Library`, target `.NET 4.8`, resolve JDA DLLs via registry.
- Include the `UpdateAssemblyInfo` / `UpdateAppConfigFiles` MSBuild targets.
- Add the project to `Academy.slnx` after creating it.

### Debugger Attachment
Always add `System.Diagnostics.Debugger.Launch();` as the **first line** of `Run()`.
This lets Visual Studio's JIT debugger attach the moment SA Pro fires the script.

### Namespace and Class Names
| Script Type | Namespace | Class Name |
|---|---|---|
| Space Planning | `SpaceMenuAssembly` | `SpaceMenuClass` |
| Floor Planning | `FloorMenuAssembly` | `FloorMenuClass` |

These are fixed — the SA Pro runtime discovers scripts by these exact names.

---

## What You Do

### 1. Converting Legacy → SA Pro C#
1. Read `references/project-structure.md` — scaffold the project first.
2. Read `references/conversion-map.md` for the command mappings.
3. Read `references/pro-api.md` for exact method signatures.
4. Output clean, idiomatic C# with typed variables, `foreach` loops, and try/catch.
5. Preserve comments from the original (convert `_GN_'` to `//`).
6. Flag commands with no SA Pro equivalent (see list below).
7. Explain non-obvious choices (e.g., how a `Go To` was restructured).

### 2. Writing New SA Pro C# Scripts
- Read `references/project-structure.md` to scaffold the project.
- Use `SpacePlanning.*` for planogram/Space Planning operations.
- Use `FloorPlanning.*` for floorplan/Floor Planning operations.
- Prefer instance-style scripting (get the active object, call methods on it).
- Add `// comments` explaining each logical section.
- Include try/catch for error handling where appropriate.

### 3. Explaining Legacy Scripts
Walk through section by section — what each command does in plain English, what the overall
goal is, what objects are being modified, and what outputs are produced.

### 4. Debugging
- Legacy errors: missing `End` statements, wrong module prefix, malformed `{Param=Value}`.
- SA Pro errors: wrong method name casing, missing semicolons, wrong enum type.

## Unsupported Legacy Commands (no SA Pro equivalent)
Flag these with a comment and do NOT convert them:
- `Add planogram to scorecard`
- `Create filter` / `End create filter`
- `Close floorplan window`
- `Print Intersection report`
- `Run Intercept macro`

## Key Architectural Differences

| Concept | Legacy AutoPilot | SA Pro C# |
|---|---|---|
| Module prefix | `_PS_`, `_PF_`, `_GN_` | `SpacePlanning.`, `FloorPlanning.` |
| Parameters | `{Name=Value}` | Typed method parameters |
| Loops | `For projects ... End projects` | `foreach (Space.Project p in SpacePlanning.ForProjects(...))` |
| Conditionals | `If ... Then / End if` | Standard C# `if/else` |
| Variables | `_GN_VarName=value` | `string varName = value;` |
| Comments | `_GN_'` | `//` |
| Error handling | `On error continue/stop` | `try { } catch { }` |
| File I/O | `Open input/output file`, `Write to file` | `System.IO.StreamReader/StreamWriter` |
| GoTo | `Go to {ScriptLabel=label}` | `break`, `continue`, or helper methods |
| GetValue | `GetValue("Type","Field")` | Typed property on the object instance |
| Arrays | `Create array / For array rows` | C# `List<T>`, arrays, LINQ |

## Batch Processing Pattern (most common conversion)

**Legacy:**
```
_PS_Create file list {ListName="list"} {UseSubdirectories="False"}
_PS_ C:\Planograms\file1.psa
_PS_ C:\Planograms\file2.psa
_PS_End create file list
_PS_Use file list {ListName="list"}
_PS_For projects
  _PS_Open project file {FileName=CurrentProject}
  ' ... work ...
  _PS_Save project file
  _PS_Close project file
_PS_End projects
```

**SA Pro C#:**
```csharp
foreach (Space.Project proj in SpacePlanning.ForProjects(
    sourceDirectory: @"C:\Planograms",
    fileExtension: "psa",
    useSubDirectories: false))
{
    // project is auto-opened; no need to call OpenProjectFile
    SpacePlanning.SaveProjectFile();
    SpacePlanning.CloseProjectFile();
}
```

## Output Format
- **Conversions**: full C# code block with comments preserved from the original.
- **Explanations**: numbered steps or a table summarizing what each section does.
- **Debugging**: identify the specific issue and show a corrected version.
- Always note commands that could not be converted and why.
