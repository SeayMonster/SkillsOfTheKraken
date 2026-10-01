$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\scripts\PackageLib.ps1')

Describe 'Get-Tier' {
    It 'runs Schema first' { Get-Tier 'P/SQL/Schema/ckbcustom.sql' | Should Be -2 }
    It 'runs Cleanup before types' { Get-Tier 'P/SQL/Cleanup/ckbcustom.x.sql' | Should Be -1 }
    It 'keeps types at 0' { Get-Tier 'P/SQL/Types/t.sql' | Should Be 0 }
    It 'keeps tables at 1' { Get-Tier 'P/SQL/Tables/ckbcustom.cx_job.sql' | Should Be 1 }
    It 'keeps procedures at 5' { Get-Tier 'P\SQL\Stored Procedures\ckbcustom.cx_a.sql' | Should Be 5 }
    It 'puts Configuration last' { Get-Tier 'P/SQL/Configuration/register_web_controls.sql' | Should Be 99 }
}

Describe 'Get-ObjectType and Get-TierSection' {
    It 'names the Schema tier' { Get-ObjectType -2 | Should Be 'Schema' }
    It 'labels the Schema section' { Get-TierSection -2 | Should Be 'SCHEMA' }
    It 'keeps the Cleanup label' { Get-TierSection -1 | Should Be 'CLEANUP (drop removed objects)' }
}

Describe 'Get-SqlObjectInfo' {
    It 'finds a CREATE OR ALTER procedure' {
        $i = Get-SqlObjectInfo "-- header`r`nCREATE OR ALTER PROCEDURE ckbcustom.cx_a @x INT AS SELECT 1"
        $i.name | Should Be 'ckbcustom.cx_a'
        $i.kind | Should Be 'procedure'
        $i.action | Should Be 'create'
    }
    It 'ignores a commented-out CREATE' {
        $i = Get-SqlObjectInfo "/* CREATE PROCEDURE ckbcustom.old */`r`n-- CREATE PROC ckbcustom.older`r`nCREATE VIEW [ckbcustom].[cx_v] AS SELECT 1 x"
        $i.name | Should Be 'ckbcustom.cx_v'
        $i.kind | Should Be 'view'
    }
    It 'reads a table type' {
        $i = Get-SqlObjectInfo "IF TYPE_ID('ckbcustom.cx_dbkey_list') IS NULL CREATE TYPE ckbcustom.cx_dbkey_list AS TABLE (DBKey INT)"
        $i.kind | Should Be 'type'
        $i.name | Should Be 'ckbcustom.cx_dbkey_list'
    }
    It 'reads a guarded CREATE TABLE' {
        $i = Get-SqlObjectInfo "IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'cx_job') BEGIN CREATE TABLE ckbcustom.cx_job (dbkey INT) END"
        $i.kind | Should Be 'table'
        $i.name | Should Be 'ckbcustom.cx_job'
    }
    It 'reads an ALTER TABLE-only script as that table' {
        $i = Get-SqlObjectInfo "IF COL_LENGTH('ckbcustom.cx_job_object','Target') IS NULL ALTER TABLE ckbcustom.cx_job_object ADD Target NVARCHAR(100) NULL;"
        $i.kind | Should Be 'table'
        $i.action | Should Be 'alter'
    }
    It 'reads a Cleanup drop' {
        $i = Get-SqlObjectInfo 'DROP VIEW IF EXISTS ckbcustom.cx_export_summary_vw;'
        $i.action | Should Be 'drop'
        $i.kind | Should Be 'view'
        $i.name | Should Be 'ckbcustom.cx_export_summary_vw'
    }
    It 'qualifies an unqualified name with ckbcustom' {
        (Get-SqlObjectInfo 'CREATE PROC cx_b AS SELECT 1').name | Should Be 'ckbcustom.cx_b'
    }
    It 'takes the first CREATE, not a temp table inside the body' {
        (Get-SqlObjectInfo 'CREATE PROCEDURE ckbcustom.p AS CREATE TABLE #t (x INT)').kind | Should Be 'procedure'
    }
    It 'treats a MERGE or CREATE SCHEMA script as a script' {
        (Get-SqlObjectInfo 'MERGE ix_web_control AS t USING (SELECT 1 a) s ON 1 = 0 WHEN NOT MATCHED THEN INSERT (a) VALUES (s.a);').kind | Should Be 'script'
        (Get-SqlObjectInfo "IF SCHEMA_ID('ckbcustom') IS NULL EXEC('CREATE SCHEMA ckbcustom')").name | Should BeNullOrEmpty
    }
}
