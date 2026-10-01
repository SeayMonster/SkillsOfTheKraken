# DeployLib.ps1 - shared by Deploy-SQL.ps1 and Rollback.ps1 in deploy-batch.zip.
# Self-contained: ADO.NET only, no batch-server helper scripts, so a package
# runs on any server that can reach CKB. Function definitions only, so the
# Pester tests can dot-source it.

# --- Connection ---

function New-DeployConnection([string]$Server, [string]$Database, [string]$User, [string]$Password) {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b['Data Source'] = $Server
    $b['Initial Catalog'] = $Database
    $b['Application Name'] = 'Kraken Deploy'
    if ([string]::IsNullOrEmpty($User)) { $b['Integrated Security'] = $true }
    else { $b['User ID'] = $User; $b['Password'] = $Password }
    $conn = New-Object System.Data.SqlClient.SqlConnection $b.ConnectionString
    $conn.Open()
    return $conn
}

function New-DeployCommand($Conn, [string]$Sql, [hashtable]$Params, [int]$Timeout) {
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $Sql
    $cmd.CommandTimeout = $Timeout
    if ($Params) {
        foreach ($k in $Params.Keys) {
            $v = $Params[$k]
            if ($null -eq $v) { $v = [DBNull]::Value }
            [void]$cmd.Parameters.AddWithValue("@$k", $v)
        }
    }
    return $cmd
}

function Invoke-DeploySql($Conn, [string]$Sql, [hashtable]$Params = @{}, [int]$Timeout = 3600) {
    $cmd = New-DeployCommand $Conn $Sql $Params $Timeout
    try { [void]$cmd.ExecuteNonQuery() } finally { $cmd.Dispose() }
}

function Get-DeployScalar($Conn, [string]$Sql, [hashtable]$Params = @{}) {
    $cmd = New-DeployCommand $Conn $Sql $Params 300
    try { $v = $cmd.ExecuteScalar() } finally { $cmd.Dispose() }
    if ($v -is [DBNull]) { return $null }
    return $v
}

function Get-DeployRows($Conn, [string]$Sql, [hashtable]$Params = @{}) {
    $cmd = New-DeployCommand $Conn $Sql $Params 300
    $table = New-Object System.Data.DataTable
    try {
        $reader = $cmd.ExecuteReader()
        $table.Load($reader)
    } finally { $cmd.Dispose() }
    return , $table
}

# --- Deploy log ---
# One row per deploy or rollback in ckbcustom.cx_deploy_log. Started first,
# then Succeeded or Failed. No environment column: a database does not know
# whether it is Test or Prod.

function Get-ManifestObjectNames($Manifest) {
    @(@($Manifest.objects) | Where-Object { $_.name } | ForEach-Object { [string]$_.name } | Select-Object -Unique)
}

function Start-DeployLog($Conn, $Manifest, [string]$Action, $BackupFolder, $RolledBackKey = $null) {
    $names = Get-ManifestObjectNames $Manifest
    $sql = @'
INSERT INTO ckbcustom.cx_deploy_log
    (Release, Build, Tag, CommitSha, Action, Result, Host, RunBy, StartedAt, BackupFolder, Objects, RolledBackKey)
OUTPUT INSERTED.dbkey
VALUES (@Release, @Build, @Tag, @CommitSha, @Action, 'Started', @Host, @RunBy, GETUTCDATE(), @BackupFolder, @Objects, @RolledBackKey)
'@
    return [int](Get-DeployScalar $Conn $sql @{
        Release       = [string]$Manifest.release
        Build         = [int]$Manifest.build
        Tag           = $Manifest.tag
        CommitSha     = $Manifest.commit
        Action        = $Action
        Host          = $env:COMPUTERNAME
        RunBy         = "$env:USERDOMAIN\$env:USERNAME"
        BackupFolder  = $BackupFolder
        Objects       = (ConvertTo-Json -InputObject @($names) -Compress)
        RolledBackKey = $RolledBackKey
    })
}

function Complete-DeployLog($Conn, [int]$Key, [string]$Result, $Message = $null, $FileCount = $null) {
    Invoke-DeploySql $Conn @'
UPDATE ckbcustom.cx_deploy_log
SET Result = @Result, FinishedAt = GETUTCDATE(), Message = @Message, FileCount = @FileCount
WHERE dbkey = @Key
'@ @{ Result = $Result; Message = $Message; FileCount = $FileCount; Key = $Key }
}

# --- Definitions ---
# OBJECT_DEFINITION returns the text as last created ("CREATE PROCEDURE ...").
# CREATE OR ALTER makes the backup rerunnable and keeps the object's
# permissions, which DROP + CREATE would lose. Comments are matched first and
# skipped, so a CREATE inside a header comment is never the one rewritten.

function ConvertTo-CreateOrAlter([string]$Definition) {
    $rx = [regex]'(?is)(?<c>/\*.*?\*/|--[^\r\n]*)|\bCREATE\s+(OR\s+ALTER\s+)?(?<k>PROCEDURE|PROC|VIEW|FUNCTION|TRIGGER)\b'
    foreach ($m in $rx.Matches($Definition)) {
        if ($m.Groups['c'].Success) { continue }
        return $Definition.Substring(0, $m.Index) + 'CREATE OR ALTER ' + $m.Groups['k'].Value + $Definition.Substring($m.Index + $m.Length)
    }
    return $Definition
}

# --- Backup ---
# Before any SQL runs, Deploy-SQL.ps1 saves the current state of every object
# the package touches into Backup\<time>\. Modules (procedures, views,
# functions, triggers) are saved as rerunnable CREATE OR ALTER scripts;
# tables and table types only as a column list, for reference -- a rollback
# cannot restore structure or data. Objects that do not exist yet are dropped
# on rollback.

function Get-SafeFileName([string]$Name) { $Name -replace '[\\/:*?"<>|]', '_' }

function Get-DropKeyword([string]$Kind) {
    switch ($Kind) {
        'procedure' { 'PROCEDURE' }
        'view' { 'VIEW' }
        'function' { 'FUNCTION' }
        'trigger' { 'TRIGGER' }
        'type' { 'TYPE' }
        'table' { 'TABLE' }
        default { $null }
    }
}

function Write-ColumnReference($Table, [string]$Name, [string]$Path) {
    $lines = @("$Name -- reference only, not restored by Rollback.ps1", '')
    foreach ($r in $Table.Rows) {
        $nullText = if ($r.is_nullable) { 'NULL' } else { 'NOT NULL' }
        $lines += ('{0,-32} {1}({2},{3},{4}) {5}' -f $r.name, $r.type_name, $r.max_length, $r.precision, $r.scale, $nullText)
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

# New objects are dropped on rollback: modules first, then types (a type
# cannot go while a module still uses it). A new table is listed commented
# out -- dropping it would also drop every row written since the deploy.
function Write-RollbackDrops($Objects, [string]$Path) {
    $order = @{ procedure = 1; trigger = 1; function = 2; view = 3; type = 4; table = 5 }
    $lines = @('-- Objects this deploy created new. Rollback.ps1 runs this file first.')
    foreach ($o in (@($Objects) | Sort-Object { $order[$_.kind] })) {
        $kw = Get-DropKeyword $o.kind
        if (-not $kw) { continue }
        if ($o.kind -eq 'table') { $lines += "-- DROP TABLE IF EXISTS $($o.name);   -- new table: uncomment to remove it and its rows" }
        else { $lines += "DROP $kw IF EXISTS $($o.name);" }
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

# Saves one object; returns 'existed', 'reference' or 'new'.
function Save-ObjectBackup($Conn, $Object, [string]$Folder) {
    $file = Get-SafeFileName $Object.name
    $columns = @'
SELECT c.name, TYPE_NAME(c.user_type_id) AS type_name, c.max_length, c.precision, c.scale, c.is_nullable
FROM sys.columns c
WHERE c.object_id = @id
ORDER BY c.column_id
'@
    if ($Object.kind -eq 'type') {
        $typeTable = Get-DeployScalar $Conn 'SELECT type_table_object_id FROM sys.table_types WHERE user_type_id = TYPE_ID(@n)' @{ n = $Object.name }
        if ($null -eq $typeTable) { return 'new' }
        Write-ColumnReference (Get-DeployRows $Conn $columns @{ id = $typeTable }) $Object.name (Join-Path $Folder "$file.reference.txt")
        return 'reference'
    }
    $id = Get-DeployScalar $Conn 'SELECT OBJECT_ID(@n)' @{ n = $Object.name }
    if ($null -eq $id) { return 'new' }
    $type = ([string](Get-DeployScalar $Conn 'SELECT type FROM sys.objects WHERE object_id = @id' @{ id = $id })).Trim()
    if (@('P', 'V', 'FN', 'IF', 'TF', 'TR') -contains $type) {
        $def = Get-DeployScalar $Conn 'SELECT OBJECT_DEFINITION(@id)' @{ id = $id }
        if ($null -eq $def) {
            Set-Content -LiteralPath (Join-Path $Folder "$file.reference.txt") -Value "$($Object.name) -- definition not readable (encrypted); not restored by Rollback.ps1" -Encoding UTF8
            return 'reference'
        }
        [IO.File]::WriteAllText((Join-Path $Folder "$file.sql"), (ConvertTo-CreateOrAlter $def), [Text.Encoding]::UTF8)
        return 'existed'
    }
    Write-ColumnReference (Get-DeployRows $Conn $columns @{ id = $id }) $Object.name (Join-Path $Folder "$file.reference.txt")
    return 'reference'
}

function Backup-DeployObjects($Conn, $Manifest, [string]$Folder, [int]$LogKey) {
    New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    $entries = New-Object System.Collections.Generic.List[object]
    $drops = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($o in @($Manifest.objects)) {
        if (-not $o.name -or $seen.ContainsKey([string]$o.name)) { continue }
        $seen[[string]$o.name] = $true
        $state = Save-ObjectBackup $Conn $o $Folder
        # A Cleanup script that drops something already gone has nothing to undo.
        if ($state -eq 'new' -and $o.action -ne 'drop') { $drops.Add($o) }
        $entries.Add([PSCustomObject]@{ name = [string]$o.name; kind = $o.kind; action = $o.action; state = $state })
    }
    # .ToArray(), not @(): PowerShell 5.1 throws "Argument types do not match"
    # wrapping a List[object] that holds ConvertFrom-Json objects in @().
    Write-RollbackDrops $drops.ToArray() (Join-Path $Folder '00_rollback_drops.sql')
    $bm = [ordered]@{
        logKey    = $LogKey
        release   = $Manifest.release
        build     = $Manifest.build
        tag       = $Manifest.tag
        createdAt = (Get-Date -Format 'o')
        host      = $env:COMPUTERNAME
        server    = (Get-DeployScalar $Conn 'SELECT @@SERVERNAME')
        database  = $Conn.Database
        objects   = $entries.ToArray()
    }
    ConvertTo-Json -InputObject $bm -Depth 5 | Set-Content (Join-Path $Folder 'backup-manifest.json') -Encoding UTF8
    return $entries.ToArray()
}
