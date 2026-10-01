$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\templates\batch\DeployLib.ps1')

Describe 'ConvertTo-CreateOrAlter' {
    It 'rewrites CREATE PROCEDURE' {
        ConvertTo-CreateOrAlter 'CREATE PROCEDURE ckbcustom.a AS SELECT 1' | Should Be 'CREATE OR ALTER PROCEDURE ckbcustom.a AS SELECT 1'
    }
    It 'normalizes an existing CREATE OR ALTER' {
        ConvertTo-CreateOrAlter 'create or alter view v as select 1 x' | Should Be 'CREATE OR ALTER view v as select 1 x'
    }
    It 'skips a CREATE inside a header comment' {
        $d = "/* CREATE PROCEDURE old */`r`n-- create proc older`r`nCREATE   PROC ckbcustom.a AS SELECT 1"
        ConvertTo-CreateOrAlter $d | Should Be "/* CREATE PROCEDURE old */`r`n-- create proc older`r`nCREATE OR ALTER PROC ckbcustom.a AS SELECT 1"
    }
    It 'rewrites only the first CREATE' {
        ConvertTo-CreateOrAlter 'CREATE FUNCTION f() RETURNS INT AS BEGIN RETURN 1 END' | Should Be 'CREATE OR ALTER FUNCTION f() RETURNS INT AS BEGIN RETURN 1 END'
        ConvertTo-CreateOrAlter 'CREATE PROC a AS CREATE TABLE #t (x INT)' | Should Be 'CREATE OR ALTER PROC a AS CREATE TABLE #t (x INT)'
    }
}

Describe 'Get-ManifestObjectNames' {
    It 'returns unique named objects only' {
        $m = [PSCustomObject]@{ objects = @(
            [PSCustomObject]@{ name = 'ckbcustom.a' },
            [PSCustomObject]@{ name = $null },
            [PSCustomObject]@{ name = 'ckbcustom.a' },
            [PSCustomObject]@{ name = 'ckbcustom.b' }) }
        (Get-ManifestObjectNames $m) -join ',' | Should Be 'ckbcustom.a,ckbcustom.b'
    }
}

Describe 'Write-RollbackDrops' {
    $path = Join-Path $TestDrive '00_rollback_drops.sql'
    Write-RollbackDrops @(
        [PSCustomObject]@{ name = 'ckbcustom.t'; kind = 'type' },
        [PSCustomObject]@{ name = 'ckbcustom.tbl'; kind = 'table' },
        [PSCustomObject]@{ name = 'ckbcustom.v'; kind = 'view' },
        [PSCustomObject]@{ name = 'ckbcustom.p'; kind = 'procedure' }) $path
    $lines = @(Get-Content $path)
    It 'drops modules before the type' {
        $p = [array]::IndexOf($lines, 'DROP PROCEDURE IF EXISTS ckbcustom.p;')
        $t = [array]::IndexOf($lines, 'DROP TYPE IF EXISTS ckbcustom.t;')
        $p | Should BeGreaterThan 0
        $t | Should BeGreaterThan $p
    }
    It 'leaves a new table commented out' {
        ($lines | Where-Object { $_ -match 'TABLE' }) | Should Match '^-- DROP TABLE IF EXISTS ckbcustom.tbl;'
    }
}

Describe 'Get-SafeFileName' {
    It 'keeps schema.name' { Get-SafeFileName 'ckbcustom.cx_a' | Should Be 'ckbcustom.cx_a' }
    It 'replaces path characters' { Get-SafeFileName 'a/b:c' | Should Be 'a_b_c' }
}
