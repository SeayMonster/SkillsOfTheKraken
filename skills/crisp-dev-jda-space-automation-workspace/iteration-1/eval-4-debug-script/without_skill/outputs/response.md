# Bug Analysis: SA Pro Script Crashes After First Project

## The Bug

The script has a hardcoded output file path in the `ExportImage` call:

```csharp
SpacePlanning.ExportImage(@"C:\Output\image.jpg", ExportMethod.JPEG, 1600, 900);
```

This path never changes between iterations. On the first project the file is written successfully. On the second project, SA Pro attempts to write to the same `image.jpg` path, causing a file-access collision that crashes the script.

## The Fix

Generate a unique output path per project and per planogram:

```csharp
foreach (Space.Project proj in SpacePlanning.ForProjects(sourceDirectory: @"C:\Planograms", fileExtension: "psa", useSubDirectories: false))
{
    foreach (Space.Planogram pog in SpacePlanning.ForPlanograms())
    {
        string outputPath = $@"C:\Output\{proj.Name}_{pog.Name}.jpg";
        SpacePlanning.ExportImage(outputPath, ExportMethod.JPEG, 1600, 900);
    }
    SpacePlanning.SaveProjectFile();
    SpacePlanning.CloseProjectFile();
}
```

**Root cause:** The static hardcoded export path means every project/planogram tries to write to the same file. The write on iteration 2 collides with the file already on disk.

**Fix:** Incorporate `proj.Name` and/or `pog.Name` into the output filename so each export targets a unique path.
