# Add Model Class: PlanogramSummary

Following the Crisp/Blue Yonder C# coding conventions, here is the new model class.

## File: `Models\PlanogramSummary.cs`

Place this file in the `Models\` folder of your project. Update the namespace to match your project's root namespace.

```csharp
namespace SpaceMenuAssembly.Models
{
    internal class PlanogramSummary
    {
        public int PlanogramKey { get; set; }
        public string Name { get; set; }
        public string StoreNumber { get; set; }
        public double Width { get; set; }
        public double Height { get; set; }
        public double EffectiveDate { get; set; }
    }
}
```

## Notes

- **Visibility**: `internal` — models are internal unless consumed cross-assembly.
- **Auto-properties only**: No constructors, no backing fields, no methods. This is a pure data container.
- **`EffectiveDate` as `double`**: Consistent with the JDA API convention where date fields are stored as OLE Automation doubles (use `DateTime.FromOADate(model.EffectiveDate)` when displaying or comparing).
- **No null-coalescing on string properties**: Per JDA API conventions, string properties default to empty string when mapped from the JDA API.
- **Namespace**: Replace `SpaceMenuAssembly` with your project's actual root namespace + `.Models`.
