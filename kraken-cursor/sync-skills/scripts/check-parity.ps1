#Requires -Version 5.1
<#
.SYNOPSIS
  Fail if the kraken-cursor port has drifted from the skills/ gold standard.
.DESCRIPTION
  skills/ is the gold standard; kraken-cursor/ is its Cursor port. Some files
  are translated on purpose (see TRANSLATION.md), others must stay byte
  identical. kraken-cursor/parity.json declares which is which.

  Three failure modes:
    1. A file in mustMatch differs between the two trees.
    2. A file in mustMatch is missing from either tree.
    3. A file exists in both trees but is classified in neither list, so
       nobody has decided whether it is allowed to diverge.

  Exits 1 on any failure so CI can gate on it. audit-sync.ps1 is the
  companion report: it compares folder coverage and is advisory only. This
  script deliberately does not use file timestamps -- a git checkout rewrites
  them all, so mtime says nothing in CI.
.PARAMETER RepoRoot
  Repository root. Defaults to three levels above this script.
#>
param(
    [string]$RepoRoot = (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$goldRoot   = Join-Path $RepoRoot 'skills'
$cursorRoot = Join-Path $RepoRoot 'kraken-cursor'
$manifest   = Join-Path $cursorRoot 'parity.json'

if (-not (Test-Path $manifest)) { Write-Error "parity.json not found at $manifest"; exit 1 }

$cfg = Get-Content $manifest -Raw | ConvertFrom-Json
$mustMatch = @($cfg.mustMatch)
$adapted   = @($cfg.adapted)
$failures  = New-Object System.Collections.ArrayList

function Get-Sha([string]$path) { (Get-FileHash -Path $path -Algorithm SHA256).Hash }

# --- 1 + 2: declared must-match files are present and identical ---
foreach ($rel in $mustMatch) {
    $g = Join-Path $goldRoot $rel
    $c = Join-Path $cursorRoot $rel
    if (-not (Test-Path $g)) { [void]$failures.Add("MISSING in skills/        : $rel"); continue }
    if (-not (Test-Path $c)) { [void]$failures.Add("MISSING in kraken-cursor/ : $rel"); continue }
    if ((Get-Sha $g) -ne (Get-Sha $c)) {
        [void]$failures.Add("DRIFTED                   : $rel")
    }
}

# --- 3: every file shared by both trees is classified ---
# Only folders that exist on both sides are considered; a skill that has not
# been ported yet is audit-sync's problem, not a parity failure.
$skipCursor = @('sync-skills')
$goldSkills = Get-ChildItem $goldRoot -Directory -ErrorAction SilentlyContinue |
              Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
              Select-Object -ExpandProperty Name

$unclassified = New-Object System.Collections.ArrayList
foreach ($skill in $goldSkills) {
    if ($skipCursor -contains $skill) { continue }
    # Forward slashes: this runs on the Linux CI runner, where a backslash is
    # a legal filename character and Join-Path will not translate it.
    $gDir = Join-Path $goldRoot   "$skill/scripts"
    $cDir = Join-Path $cursorRoot "$skill/scripts"
    if (-not (Test-Path $gDir) -or -not (Test-Path $cDir)) { continue }
    foreach ($f in (Get-ChildItem $gDir -File -ErrorAction SilentlyContinue)) {
        $rel = "$skill/scripts/$($f.Name)"
        if (-not (Test-Path (Join-Path $cDir $f.Name))) { continue }
        if ($mustMatch -contains $rel -or $adapted -contains $rel) { continue }
        [void]$unclassified.Add($rel)
    }
}
foreach ($u in $unclassified) {
    [void]$failures.Add("UNCLASSIFIED              : $u  (add to mustMatch or adapted in kraken-cursor/parity.json)")
}

# --- report ---
Write-Host "Cursor port parity check"
Write-Host "  gold   : $goldRoot"
Write-Host "  cursor : $cursorRoot"
Write-Host "  declared must-match : $($mustMatch.Count)"
Write-Host "  declared adapted    : $($adapted.Count)"
Write-Host ""

if ($failures.Count -eq 0) {
    Write-Host "PASS - kraken-cursor is in sync with skills/ for every declared file."
    exit 0
}

Write-Host "FAIL - $($failures.Count) problem(s):"
foreach ($f in $failures) { Write-Host "  $f" }
Write-Host ""
Write-Host "If a difference is a deliberate Cursor translation, add the path to"
Write-Host "'adapted' in kraken-cursor/parity.json with a reason. Otherwise copy the"
Write-Host "gold file over the cursor one -- skills/ is the source of truth."
exit 1
