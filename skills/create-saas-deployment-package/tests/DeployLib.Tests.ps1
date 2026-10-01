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
