# SA Pro C# Script: Set Planogram Description from Filename

## Project Structure

```
SetDescriptionFromFilename\
  SetDescriptionFromFilename\
    SetDescriptionFromFilename.csproj
    SpaceMenuClass.cs
    HelperClasses\
      CommandFactory.cs
      ConfigurationHelper.cs
    Properties\
      AssemblyInfo.cs
    App.Config
    packages.config
```

## SpaceMenuClass.cs

```csharp
#region
using JDA.Intactix.Automation;
using SpaceMenuAssembly.HelperClasses;
using Serilog.Core;
using System;
using System.Diagnostics;
using System.IO;
using Space = JDA.Intactix.Automation.Space;
#endregion

namespace SpaceMenuAssembly
{
    /// <summary>
    /// Loops through all .psa files in C:\Planograms\Active and sets the Description
    /// (Desc1) field on each planogram to match the filename without the extension.
    /// </summary>
    [Serializable]
    public class SpaceMenuClass : Script
    {
        private Logger _logger;

        public SpaceMenuClass() : base(0) { }
        public SpaceMenuClass(int nSpaceOrFloor) : base(nSpaceOrFloor) { }

        public override void Run(bool isSilentMode = true)
        {
            Debugger.Launch();

            _logger = ConfigurationHelper.CreateLogger();
            _logger.Information("Starting Run()");

            try
            {
                if (SpacePlanning.GetObjectCount("Project") > 0)
                    SpacePlanning.CloseProjectFile();

                string sourceDirectory = @"C:\Planograms\Active";

                if (!Directory.Exists(sourceDirectory))
                {
                    _logger.Warning($"Source directory does not exist: {sourceDirectory}");
                    return;
                }

                foreach (Space.Project proj in SpacePlanning.ForProjects(
                    sourceDirectory: sourceDirectory,
                    fileExtension: "psa",
                    useSubDirectories: false))
                {
                    string fileName = Path.GetFileNameWithoutExtension(proj.FileName);
                    _logger.Information($"Processing: {proj.FileName}");

                    try
                    {
                        foreach (Space.Planogram pog in SpacePlanning.ForPlanograms())
                        {
                            if (pog == null)
                            {
                                _logger.Warning($"Planogram in {proj.FileName} is null — skipping");
                                continue;
                            }

                            // Set the Description (Desc 1) field to the filename without extension
                            SpacePlanning.SetPlanogramField(pog.Name, "Desc 1", fileName);
                            _logger.Information($"  Set Description = \"{fileName}\" on planogram \"{pog.Name}\"");
                        }

                        SpacePlanning.SaveProjectFile();
                        SpacePlanning.CloseProjectFile();
                        _logger.Information($"Saved and closed: {proj.FileName}");
                    }
                    catch (Exception ex)
                    {
                        _logger.Error(ex, $"Error processing {proj.FileName}");
                        try { SpacePlanning.CloseProjectFile(); } catch { }
                    }
                }

                _logger.Information("Finished Run()");
            }
            catch (Exception ex)
            {
                _logger?.Error(ex, "Run Exception");
                throw;
            }
        }
    }
}
```

## Key Design Decisions

- `Debugger.Launch()` is the first line of `Run()` per the non-negotiable rule.
- `SpacePlanning.ForProjects(sourceDirectory, "psa", useSubDirectories: false)` handles opening each file automatically.
- `Path.GetFileNameWithoutExtension(proj.FileName)` strips both the directory path and `.psa` extension.
- `SpacePlanning.SetPlanogramField(pog.Name, "Desc 1", fileName)` writes the value — direct property assignment is read-only on the JDA model.
- Per-file try/catch logs errors and continues to the next file rather than aborting the batch.
