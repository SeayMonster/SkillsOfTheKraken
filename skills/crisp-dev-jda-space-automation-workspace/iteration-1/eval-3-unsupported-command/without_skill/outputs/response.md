# Converted SA Pro C# Code

```csharp
using System;
using JDA.SpaceAutomation;

public class Script : ScriptBase
{
    public override void Execute()
    {
        foreach (Project project in Application.Projects)
        {
            project.Open();

            foreach (Planogram planogram in project.Planograms)
            {
                planogram.AddToScorecard(); // placeholder - see notes

                planogram.ExportImage(
                    layoutFile: "[CurrentView]",
                    imageType: "JPEG (*.jpg)",
                    file: @"C:\Output\image.jpg"
                );
            }

            project.Close();
        }
    }
}
```

## Notes

### Unsupported Command

The `_PS_Add planogram to scorecard` command does not have a known equivalent in the SA Pro C# API. The `AddToScorecard()` method used above is a placeholder and may not exist. Consult the SA Pro C# API reference for the correct method, or check whether scorecard operations are exposed through a `Scorecard` or `Report` object.

All other commands follow standard SA Pro C# patterns and should work as written.
