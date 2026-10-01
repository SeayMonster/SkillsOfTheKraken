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
