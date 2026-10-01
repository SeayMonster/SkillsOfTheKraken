$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tpl = Join-Path $here '..\templates\batch'
. (Join-Path $tpl 'DeployLib.ps1')
$Server = 'cx-lpt676\dev2022'
$Db = 'ckb'

function New-TestPackage([string]$Dir, [int]$Build, [string]$Value) {
    New-Item -ItemType Directory (Join-Path $Dir 'SQL') -Force | Out-Null
    Copy-Item (Join-Path $tpl '*') $Dir
    $manifest = [ordered]@{
        release = 'zz-test'; build = $Build; tag = "deploy/zz-test_0$Build"; commit = ('0' * 40)
        objects = @(
            [ordered]@{ file = 'SQL/001_proc.sql'; name = 'ckbcustom.zz_kraken_deploy_test'; kind = 'procedure'; action = 'create' },
            [ordered]@{ file = 'SQL/002_view.sql'; name = 'ckbcustom.zz_kraken_deploy_new'; kind = 'view'; action = 'create' })
    }
    ConvertTo-Json $manifest -Depth 4 | Set-Content (Join-Path $Dir 'manifest.json')
    Set-Content (Join-Path $Dir 'SQL\001_proc.sql') "CREATE OR ALTER PROCEDURE ckbcustom.zz_kraken_deploy_test AS SELECT $Value AS v"
    Set-Content (Join-Path $Dir 'SQL\002_view.sql') "CREATE OR ALTER VIEW ckbcustom.zz_kraken_deploy_new AS SELECT $Value AS v"
}

function Get-RollbackScript([string]$Dir) {
    Join-Path (@(Get-ChildItem (Join-Path $Dir 'Backup') -Directory)[0].FullName) 'Rollback.ps1'
}

Describe 'Deploy-SQL.ps1 and Rollback.ps1 against local CKB' {
    $conn = New-DeployConnection $Server $Db $null $null
    $value = { Get-DeployScalar $conn 'EXEC ckbcustom.zz_kraken_deploy_test' }
    $lastLog = { (Get-DeployRows $conn "SELECT TOP 1 Action, Result, Message FROM ckbcustom.cx_deploy_log WHERE Release = 'zz-test' ORDER BY dbkey DESC").Rows[0] }

    Invoke-DeploySql $conn "DROP VIEW IF EXISTS ckbcustom.zz_kraken_deploy_new; IF OBJECT_ID('ckbcustom.cx_deploy_log','U') IS NOT NULL DELETE FROM ckbcustom.cx_deploy_log WHERE Release = 'zz-test';"
    Invoke-DeploySql $conn 'CREATE OR ALTER PROCEDURE ckbcustom.zz_kraken_deploy_test AS SELECT 1 AS v'

    $a = Join-Path $TestDrive 'a'; New-TestPackage $a 1 '2'
    $b = Join-Path $TestDrive 'b'; New-TestPackage $b 2 '3'

    It 'deploys build 1 after backing up' {
        & (Join-Path $a 'Deploy-SQL.ps1') -Server $Server -Database $Db
        & $value | Should Be 2
        $bk = Split-Path (Get-RollbackScript $a) -Parent
        Get-Content (Join-Path $bk 'ckbcustom.zz_kraken_deploy_test.sql') -Raw | Should Match 'CREATE OR ALTER PROCEDURE'
        Get-Content (Join-Path $bk '00_rollback_drops.sql') -Raw | Should Match 'DROP VIEW IF EXISTS ckbcustom.zz_kraken_deploy_new;'
        (& $lastLog).Result | Should Be 'Succeeded'
    }
    It 'deploys build 2 over it' {
        & (Join-Path $b 'Deploy-SQL.ps1') -Server $Server -Database $Db
        & $value | Should Be 3
    }
    It 'refuses to roll back build 1 while build 2 stands' {
        { & (Get-RollbackScript $a) -Server $Server -Database $Db } | Should Throw
        & $value | Should Be 3
    }
    It 'rolls back newest first' {
        & (Get-RollbackScript $b) -Server $Server -Database $Db
        & $value | Should Be 2
        & (Get-RollbackScript $a) -Server $Server -Database $Db
        & $value | Should Be 1
        Get-DeployScalar $conn "SELECT OBJECT_ID('ckbcustom.zz_kraken_deploy_new')" | Should BeNullOrEmpty
        (& $lastLog).Action | Should Be 'Rollback'
    }
    It 'stops on a broken file and logs it' {
        $c = Join-Path $TestDrive 'c'; New-TestPackage $c 3 '4'
        Set-Content (Join-Path $c 'SQL\001_proc.sql') 'CREATE OR ALTER PROCEDURE ckbcustom.zz_kraken_deploy_test AS SELEC 4'
        { & (Join-Path $c 'Deploy-SQL.ps1') -Server $Server -Database $Db } | Should Throw
        $row = & $lastLog
        $row.Result | Should Be 'Failed'
        $row.Message | Should Match '001_proc.sql'
        & $value | Should Be 1
    }

    Invoke-DeploySql $conn "DROP PROCEDURE IF EXISTS ckbcustom.zz_kraken_deploy_test; DROP VIEW IF EXISTS ckbcustom.zz_kraken_deploy_new; DELETE FROM ckbcustom.cx_deploy_log WHERE Release = 'zz-test';"
    $conn.Close()
}
