# Legacy → SA Pro C# Conversion

## Unsupported Command

`_PS_Add planogram to scorecard` has **no SA Pro equivalent** and is on the skill's explicit unsupported list. It is preserved as a `// UNSUPPORTED` comment. No attempt is made to work around it.

## Conversion Notes

| Legacy Command | SA Pro Equivalent | Notes |
|---|---|---|
| `_PS_For projects` | `SpacePlanning.ForProjects(...)` | Source directory read from App.Config |
| `_PS_Open project file {FileName=CurrentProject}` | *(auto-opened by ForProjects)* | No explicit call needed |
| `_PS_For planograms` | `SpacePlanning.ForPlanograms()` | Direct equivalent |
| `_PS_Add planogram to scorecard` | **NOT SUPPORTED** | No SA Pro equivalent; flagged as comment |
| `_PS_Export image` | `SpacePlanning.ExportImage(@"C:\Output\image.jpg", ExportMethod.JPEG, width, height)` | `[CurrentView]` is default in SA Pro; width/height required, defaulting to 1600x900 |
| `_PS_Close project file` | `SpacePlanning.CloseProjectFile()` | Direct equivalent |

## SpaceMenuClass.cs

```csharp
namespace SpaceMenuAssembly
{
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
                foreach (Space.Project proj in SpacePlanning.ForProjects(
                    sourceDirectory: ConfigurationHelper.GetConfigSetting("SourceDirectory"),
                    fileExtension: "psa",
                    useSubDirectories: false))
                {
                    try
                    {
                        foreach (Space.Planogram pog in SpacePlanning.ForPlanograms())
                        {
                            // UNSUPPORTED: _PS_Add planogram to scorecard
                            // There is no SA Pro equivalent for this legacy command.
                            // This step is intentionally skipped.

                            SpacePlanning.ExportImage(
                                @"C:\Output\image.jpg",
                                ExportMethod.JPEG,
                                width: 1600,
                                height: 900);

                            _logger.Information($"Exported image for planogram: {pog.Name}");
                        }

                        SpacePlanning.CloseProjectFile();
                        _logger.Information($"Closed project: {proj.Name}");
                    }
                    catch (Exception ex)
                    {
                        _logger.Error(ex, $"Error processing project: {proj.Name}");
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

## Summary

- `_PS_Add planogram to scorecard` is unsupported — preserved as a `// UNSUPPORTED` comment.
- `SpacePlanning.ExportImage` requires explicit width/height (absent from legacy script) — defaulted to 1600x900.
- Source directory read from App.Config rather than hardcoded.
- Full project scaffold follows `references/project-structure.md`.
