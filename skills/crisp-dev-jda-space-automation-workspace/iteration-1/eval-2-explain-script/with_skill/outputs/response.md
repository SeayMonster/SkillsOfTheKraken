# Script Explanation: Delete Zero-Capacity Positions

## Step-by-Step

**Step 1 — `_PS_For projects` / `_PS_End projects`**
The outer loop. Iterates over every project in scope (the active file list, or the currently open project if none is set). Each iteration makes one project the current context.

**Step 2 — `_PS_For planograms` / `_PS_End planograms`**
Inside each project, this loop iterates over every planogram in that project. When `GetValue("Position",...)` and `_PS_Delete position` are used inside a planogram loop, the engine implicitly walks each position within the current planogram.

**Step 3 — `_GN_If GetValue("Position","Capacity")=0 Then`**
For the current position, reads the `Capacity` field. If the value equals zero, the condition is true and the body executes. If capacity is anything other than zero, the body is skipped and the engine moves to the next position.

**Step 4 — `_PS_Delete position {Option="CurrentPosition"}`**
Deletes the current position from the planogram. `{Option="CurrentPosition"}` targets whichever position is active in the implicit position iteration — not a named or keyed position.

**Step 5 — `_GN_End if`**
Closes the conditional block. Returns to iterating the next position.

## Overall Purpose

This script performs a **cleanup sweep** across all projects and their planograms. Its sole job is to **remove any shelf position whose capacity is zero**. A zero-capacity position is a placeholder — it occupies a slot but holds no product facing. Deleting these keeps planograms clean and prevents them from skewing space calculations or reports.

## Summary Table

| Line | Command | What It Does |
|---|---|---|
| 1 | `_PS_For projects` | Loop over every project in scope |
| 2 | `_PS_For planograms` | Loop over every planogram in the current project |
| 3 | `_GN_If GetValue("Position","Capacity")=0 Then` | Check if current position has zero capacity |
| 4 | `_PS_Delete position {Option="CurrentPosition"}` | Delete the position if capacity is 0 |
| 5 | `_GN_End if` | End the conditional |
| 6 | `_PS_End planograms` | End the planogram loop |
| 7 | `_PS_End projects` | End the project loop |
