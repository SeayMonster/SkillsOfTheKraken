# PackageLib.ps1 - helpers for build-deployment-package.ps1.
# Dot-sourced by the build script, the watcher and the Pester tests, so it has
# no side effects at load time: function definitions only.

# --- SQL tiers ---
# Run order of a full install. Schema first, so tables have somewhere to go;
# Cleanup next, so dead objects are gone before anything is created.

function Get-Tier([string]$path) {
    $leaf = Split-Path $path -Leaf
    if ($path -match '[\\/]Schema[\\/]') { return -2 }
    if ($path -match '[\\/]Cleanup[\\/]') { return -1 }
    if ($path -match '[\\/]Types[\\/]') { return 0 }
    if ($path -match '[\\/]Tables[\\/]' -and $leaf -notmatch '^Populate') { return 1 }
    if ($leaf -match '^Populate|^ckbcustom\.Populate') { return 2 }
    if ($path -match '[\\/]Functions[\\/]') { return 3 }
    if ($path -match '[\\/]Views[\\/]') { return 4 }
    if ($path -match '[\\/]Stored Procedures[\\/]|[\\/]Store Procedures[\\/]|[\\/]Procedures[\\/]') { return 5 }
    return 99
}

function Get-ObjectType([int]$tier) {
    switch ($tier) {
        -2 { 'Schema' }
        -1 { 'Cleanup' }
        0 { 'Type' }
        1 { 'Table' }
        2 { 'Data' }
        3 { 'Function' }
        4 { 'View' }
        5 { 'Stored Procedure' }
        default { 'Unknown' }
    }
}

function Get-TierSection([int]$tier) {
    switch ($tier) {
        -2 { 'SCHEMA' }
        -1 { 'CLEANUP (drop removed objects)' }
        0 { 'TYPES' }
        1 { 'TABLES' }
        2 { 'DATA' }
        3 { 'FUNCTIONS' }
        4 { 'VIEWS' }
        5 { 'STORED PROCEDURES' }
        default { 'UNKNOWN' }
    }
}

# --- SQL object detection ---
# Which object a script creates, alters or drops, so the deploy can back it up
# first. Comments are stripped before matching so a commented-out CREATE is
# never mistaken for the real one. The first match wins, so a temp table
# created inside a procedure body never displaces the procedure.

function ConvertTo-ObjectName([string]$raw) {
    $n = $raw -replace '[\[\]]', ''
    if ($n -notmatch '\.') { $n = "ckbcustom.$n" }
    return $n
}

function New-SqlObjectInfo($match, [string]$action) {
    $kind = $match.Groups['kind'].Value.ToLower()
    if ($kind -eq 'proc') { $kind = 'procedure' }
    return [PSCustomObject]@{
        name   = (ConvertTo-ObjectName $match.Groups['name'].Value)
        kind   = $kind
        action = $action
    }
}

function Get-SqlObjectInfo([string]$content) {
    $text = [regex]::Replace($content, '(?s)/\*.*?\*/', '')
    $text = [regex]::Replace($text, '(?m)--[^\r\n]*', '')
    $name = '(?<name>(\[?\w+\]?\.)?\[?\w+\]?)'
    $kinds = 'PROCEDURE|PROC|VIEW|FUNCTION|TRIGGER|TABLE|TYPE'

    $m = [regex]::Match($text, "(?i)\bCREATE\s+(OR\s+ALTER\s+)?(?<kind>$kinds)\s+$name")
    if ($m.Success) { return New-SqlObjectInfo $m 'create' }
    $m = [regex]::Match($text, "(?i)\bALTER\s+(?<kind>$kinds)\s+$name")
    if ($m.Success) { return New-SqlObjectInfo $m 'alter' }
    $m = [regex]::Match($text, "(?i)\bDROP\s+(?<kind>$kinds)\s+(IF\s+EXISTS\s+)?$name")
    if ($m.Success) { return New-SqlObjectInfo $m 'drop' }
    return [PSCustomObject]@{ name = $null; kind = 'script'; action = 'script' }
}
