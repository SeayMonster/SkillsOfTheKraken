# Bug Analysis: SA Pro Script Crashes After First Project

## Two Bugs Found

**Bug 1 — Hardcoded output path overwrites every image (the crash cause)**

```csharp
SpacePlanning.ExportImage(@"C:\Output\image.jpg", ExportMethod.JPEG, 1600, 900);
```

Every planogram in every project writes to the exact same file path. On the second planogram or second project, the file is either overwritten silently or — if SA Pro holds a file lock — throws an IO/access exception. This is the crash.

Fix: use `pog.Name` to generate a unique path per planogram:
```csharp
string safeName = pog.Name.Replace(" ", "_").Replace("'", "");
string outputPath = $@"C:\Output\{safeName}.jpg";
SpacePlanning.ExportImage(outputPath, ExportMethod.JPEG, 1600, 900);
```

**Bug 2 — Unnecessary `SaveProjectFile()` on a read-only export**

This script only exports images — it does not modify any planogram data. Calling `SaveProjectFile()` is unnecessary and in some SA Pro runtime versions raises an error when called on a non-dirty project opened via `ForProjects`. Remove it; `CloseProjectFile()` alone is correct.

## Corrected Script

```csharp
foreach (Space.Project proj in SpacePlanning.ForProjects(
    sourceDirectory: @"C:\Planograms",
    fileExtension: "psa",
    useSubDirectories: false))
{
    foreach (Space.Planogram pog in SpacePlanning.ForPlanograms())
    {
        string safeName = pog.Name.Replace(" ", "_").Replace("'", "");
        string outputPath = $@"C:\Output\{safeName}.jpg";
        SpacePlanning.ExportImage(outputPath, ExportMethod.JPEG, 1600, 900);
    }
    SpacePlanning.CloseProjectFile();
}
```
