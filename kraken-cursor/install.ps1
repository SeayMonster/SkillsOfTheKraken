#Requires -Version 5.1
<#
.SYNOPSIS
  Install kraken-cursor skills into ~/.cursor/skills/
.DESCRIPTION
  Symlinks (or copies) each kraken-cursor/*/SKILL.md skill folder to
  ~/.cursor/skills/kraken-cursor-<folder-name>/ so Cursor Agent can load them.
#>
param(
    [string]$RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$skillsRoot = Join-Path $env:USERPROFILE '.cursor\skills'

if (-not (Test-Path $skillsRoot)) {
    New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
}

$installed = @()
Get-ChildItem $RepoRoot -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName 'SKILL.md')
} | ForEach-Object {
    $skillFolder = $_.Name
    $targetName  = "kraken-cursor-$skillFolder"
    $targetPath  = Join-Path $skillsRoot $targetName
    $sourcePath  = $_.FullName

    if (Test-Path $targetPath) {
        Remove-Item $targetPath -Recurse -Force
    }

    try {
        New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath -Force | Out-Null
        $method = 'symlink'
    } catch {
        Copy-Item -Path $sourcePath -Destination $targetPath -Recurse -Force
        $method = 'copy'
    }

    $installed += [PSCustomObject]@{
        Name   = $targetName
        Path   = $targetPath
        Method = $method
    }
}

Write-Host ''
Write-Host 'kraken-cursor skills installed:' -ForegroundColor Green
foreach ($s in $installed) {
    Write-Host "  $($s.Name) ($($s.Method))" -ForegroundColor Cyan
    Write-Host "    -> $($s.Path)"
}
Write-Host ''
Write-Host 'Restart Cursor or start a new Agent chat to load skills.' -ForegroundColor Yellow
