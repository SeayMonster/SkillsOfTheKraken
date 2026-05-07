# SA Pro C# Script: Set Planogram Description from Filename

## Task

Loop through all `.psa` files in `C:\Planograms\Active` and set the `Description` field on each planogram to match the filename (without the extension).

## Script

```csharp
using System;
using System.IO;

public class SetDescriptionFromFilename
{
    public void Execute()
    {
        string folderPath = @"C:\Planograms\Active";

        string[] psaFiles = Directory.GetFiles(folderPath, "*.psa");

        foreach (string filePath in psaFiles)
        {
            string fileName = Path.GetFileNameWithoutExtension(filePath);

            PSA.Planogram pog = Application.OpenPlanogram(filePath);

            if (pog != null)
            {
                pog.Description = fileName;
                pog.Save();
                pog.Close();
                Application.WriteOutput("Updated description for: " + fileName);
            }
            else
            {
                Application.WriteOutput("Failed to open: " + filePath);
            }
        }

        Application.WriteOutput("Done. Processed " + psaFiles.Length + " planogram(s).");
    }
}
```

## Notes

- `Directory.GetFiles` with `"*.psa"` collects all planogram files.
- `Path.GetFileNameWithoutExtension` strips the `.psa` extension.
- `Application.OpenPlanogram(filePath)` opens each file and returns a `PSA.Planogram` object.
- The `Description` property is set directly on the planogram object.
- `pog.Save()` persists the change. `pog.Close()` releases the planogram from memory.
