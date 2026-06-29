#Requires -Version 5.1
<#
.SYNOPSIS
  Compare skills/ (Claude) vs kraken-cursor/ (Cursor) and report gaps.
#>
param(
    [string]$RepoRoot = (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent)
)

$claudeRoot = Join-Path $RepoRoot 'skills'
$cursorRoot = Join-Path $RepoRoot 'kraken-cursor'

$skipCursor = @('sync-skills', 'install.ps1', 'README.md', 'TRANSLATION.md')

function Get-SkillFolders($root, $exclude) {
    if (-not (Test-Path $root)) { return @() }
    Get-ChildItem $root -Directory |
        Where-Object {
            $exclude -notcontains $_.Name -and
            (Test-Path (Join-Path $_.FullName 'SKILL.md'))
        } |
        Select-Object -ExpandProperty Name |
        Sort-Object
}

$claude = Get-SkillFolders $claudeRoot @()
$cursor = Get-SkillFolders $cursorRoot $skipCursor

$missingInCursor = $claude | Where-Object { $_ -notin $cursor }
$extraInCursor   = $cursor | Where-Object { $_ -notin $claude }

$stale = @()
foreach ($name in ($claude | Where-Object { $_ -in $cursor })) {
    $src = Join-Path $claudeRoot $name
    $dst = Join-Path $cursorRoot $name
    $srcTime = (Get-ChildItem $src -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
    $dstTime = (Get-ChildItem $dst -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
    if ($srcTime -gt $dstTime) { $stale += $name }
}

$result = [PSCustomObject]@{
    repoRoot          = $RepoRoot
    claudeCount       = $claude.Count
    cursorCount       = $cursor.Count
    missingInCursor   = @($missingInCursor)
    extraInCursor     = @($extraInCursor)
    staleInCursor     = @($stale)
    needsTranslation  = @($missingInCursor)
    needsUpdate       = @($stale)
}

$result | ConvertTo-Json -Depth 4
