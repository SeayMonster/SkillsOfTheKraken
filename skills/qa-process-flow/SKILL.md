---
description: Open the QA Bot process flow guide in the browser. Shows setup steps, per-client workflow, commands reference, and edge case handling.
---

Open the QA process flow HTML guide in the default browser.

Run this PowerShell command — replace the path with wherever TechTeam_Skills is cloned on this machine:

```powershell
# Find TechTeam_Skills clone location
$skillPath = $null
$candidates = @(
    "$env:USERPROFILE\source\repos\TechTeam_Skills",
    "$env:USERPROFILE\repos\TechTeam_Skills",
    "C:\repos\TechTeam_Skills",
    "C:\source\repos\TechTeam_Skills"
)
foreach ($c in $candidates) {
    if (Test-Path "$c\skills\qa-process-flow\process-flow.html") {
        $skillPath = "$c\skills\qa-process-flow\process-flow.html"
        break
    }
}

if ($skillPath) {
    Start-Process $skillPath
    Write-Host "Opened: $skillPath"
} else {
    Write-Host "Could not locate process-flow.html. Check that TechTeam_Skills is cloned."
    Write-Host "Expected: <TechTeam_Skills>\skills\qa-process-flow\process-flow.html"
}
```
