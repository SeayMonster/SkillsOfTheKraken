# What This Script Does

This is a cleanup / data hygiene script. It loops through every project and every planogram, and deletes any position that has a Capacity of zero.

## Step-by-Step Breakdown

**Step 1: `_PS_For projects`**
Opens an outer loop that iterates over every project in the current AutoPilot workspace. Projects are the top-level containers that hold planograms.

**Step 2: `_PS_For planograms`**
Inside the project loop, opens an inner loop that iterates over every planogram within the current project.

**Step 3: `_GN_If GetValue("Position","Capacity")=0 Then`**
For each position in the current planogram, checks whether its Capacity field equals zero. `GetValue("Position","Capacity")` reads the Capacity attribute from the current Position record. A value of 0 means the position can hold no units — it is effectively empty or invalid.

**Step 4: `_PS_Delete position {Option="CurrentPosition"}`**
If the capacity is zero, deletes that position from the planogram. The `Option="CurrentPosition"` modifier tells the engine to delete the specific position currently being evaluated in context.

**Step 5: `_GN_End if` / `_PS_End planograms` / `_PS_End projects`**
Close the conditional and both loops.

## Summary

The script removes positions with zero capacity from every planogram across every project in the workspace. Zero-capacity positions are invalid shelf slots that cannot hold any product.

| Prefix | Meaning |
|--------|---------|
| `_PS_` | JDA Space Planning (planogram-level) command |
| `_GN_` | General scripting command (conditionals, logic) |
| `GetValue(...)` | Reads a named field from a named object |
| `{Option="..."}` | Modifier parameter passed to a command |
