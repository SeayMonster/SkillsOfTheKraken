$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\scripts\PackageLib.ps1')

Describe 'Get-Tier' {
    It 'runs Schema first' { Get-Tier 'P/SQL/Schema/ckbcustom.sql' | Should Be -2 }
    It 'runs Cleanup before types' { Get-Tier 'P/SQL/Cleanup/ckbcustom.x.sql' | Should Be -1 }
    It 'keeps types at 0' { Get-Tier 'P/SQL/Types/t.sql' | Should Be 0 }
    It 'accepts a singular Type folder' { Get-Tier 'FloatingShelves/CXFloatingShelf/SQL/Type/ckbcustom.cx_shelf_detail.sql' | Should Be 0 }
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

Describe 'Read-ClientConfig without client.json' {
    It 'returns the built-in defaults' {
        $c = Read-ClientConfig $TestDrive
        @($c.projects).Count | Should Be 0
        ($c.webDlls -contains '^CX\.') | Should Be $true
        ($c.vendorWebDlls -contains 'JDA.Intactix.BCAE.Resources.dll') | Should Be $true
        $c.vendorExplicit | Should Be $false
        Get-DeployTarget $c 'web' | Should Be 'U:\OpenAccess\Customization'
        Get-DeployTarget $c 'batch' | Should Be 'F:\batch\exe'
        Get-DeployTarget $c 'sapro' | Should BeNullOrEmpty
    }
}

Describe 'Read-ClientConfig with client.json' {
    $json = @'
{
  "projects": [
    { "name": "BHNConversionScript", "path": "BHN.Pog.Converter/CXBHNPogConverter", "target": "sapro" },
    { "name": "PlanogramExport", "path": "PlanogramExport", "target": "batch", "deployTo": "F:\\batch\\exe\\PogExport" },
    { "name": "OpenAccessBaseControls", "path": "OpenAccessBaseControls", "target": "web", "deployTo": "X:\\ignored" }
  ],
  "webDlls": ["^CX\\.", "^Dapper\\."],
  "vendorWebDlls": ["JDA.Intactix.BCAE.dll"],
  "targets": {
    "web":   { "saas": "U:\\OpenAccess\\Customization", "local": "C:\\OA" },
    "sapro": { "saas": "S:\\BHN\\SpaceSAProScripts" }
  }
}
'@
    Set-Content (Join-Path $TestDrive 'client.json') $json
    $c = Read-ClientConfig $TestDrive

    It 'reads the lists' {
        @($c.webDlls).Count | Should Be 2
        $c.vendorWebDlls[0] | Should Be 'JDA.Intactix.BCAE.dll'
        $c.vendorExplicit | Should Be $true
    }
    It 'resolves project folders from path, falling back to the name' {
        Get-ProjectRelPath $c 'BHNConversionScript' | Should Be 'BHN.Pog.Converter/CXBHNPogConverter'
        Get-ProjectRelPath $c 'Unlisted' | Should Be 'Unlisted'
        Resolve-ProjectPath 'C:\r' $c 'BHNConversionScript' | Should Be 'C:\r\BHN.Pog.Converter\CXBHNPogConverter'
    }
    It 'reads targets per kind and mode' {
        Get-DeployTarget $c 'sapro' | Should Be 'S:\BHN\SpaceSAProScripts'
        Get-DeployTarget $c 'web' 'local' | Should Be 'C:\OA'
        Get-DeployTarget $c 'sapro' 'local' | Should BeNullOrEmpty
        Get-DeployTarget $c 'batch' | Should Be 'F:\batch\exe'
    }
    It 'lets a batch project override with deployTo, never a web project' {
        Get-DeployTarget $c 'batch' 'saas' 'PlanogramExport' | Should Be 'F:\batch\exe\PogExport'
        Get-DeployTarget $c 'web' 'saas' 'OpenAccessBaseControls' | Should Be 'U:\OpenAccess\Customization'
    }
}

Describe 'Test-WebDll' {
    $rules = @('^CX\.', '^Dapper\.')
    $vendor = @('JDA.Intactix.BCAE.dll')
    It 'allows our DLLs' { Test-WebDll 'CX.OpenAccess.DerivedControls.dll' $rules $vendor | Should Be $true }
    It 'allows a listed vendor DLL' { Test-WebDll 'JDA.Intactix.BCAE.dll' $rules $vendor | Should Be $true }
    It 'blocks other JDA DLLs' { Test-WebDll 'JDA.Intactix.IKB.Web.dll' $rules $vendor | Should Be $false }
    It 'blocks unlisted DLLs' { Test-WebDll 'Newtonsoft.Json.dll' $rules $vendor | Should Be $false }
    It 'blocks vshost' { Test-WebDll 'CX.App.vshost.dll' $rules $vendor | Should Be $false }
}

Describe 'Find-VendorDll' {
    New-Item -ItemType Directory (Join-Path $TestDrive 'P\bin') -Force | Out-Null
    New-Item -ItemType Directory (Join-Path $TestDrive 'P\Libraries') -Force | Out-Null
    Set-Content (Join-Path $TestDrive 'P\bin\A.dll') 'x'
    Set-Content (Join-Path $TestDrive 'P\Libraries\B.dll') 'x'
    It 'prefers the build output' { Find-VendorDll (Join-Path $TestDrive 'P') 'A.dll' | Should Be (Join-Path $TestDrive 'P\bin\A.dll') }
    It 'falls back to Libraries' { Find-VendorDll (Join-Path $TestDrive 'P') 'B.dll' | Should Be (Join-Path $TestDrive 'P\Libraries\B.dll') }
    It 'returns null when missing' { Find-VendorDll (Join-Path $TestDrive 'P') 'C.dll' | Should BeNullOrEmpty }
}

Describe 'Get-NextBuild and Get-BuildTag' {
    It 'starts at 1 for a new release' { Get-NextBuild (Join-Path $TestDrive 'none') | Should Be 1 }
    It 'follows the highest build folder' {
        $r = Join-Path $TestDrive '2026-10-01'
        New-Item -ItemType Directory (Join-Path $r '01_1000') -Force | Out-Null
        New-Item -ItemType Directory (Join-Path $r '02_1400') -Force | Out-Null
        New-Item -ItemType Directory (Join-Path $r 'notes') -Force | Out-Null
        Get-NextBuild $r | Should Be 3
    }
    It 'formats the tag' { Get-BuildTag '2026-10-01' 2 | Should Be 'deploy/2026-10-01_02' }
}

Describe 'Resolve-Baseline' {
    $tags = @('deploy/2026-10-01_02', 'deploy/2026-10-01_01')
    It 'uses the requested tag when it exists' { Resolve-Baseline 'deploy/2026-10-01_01' $null $tags | Should Be 'deploy/2026-10-01_01' }
    It 'uses deploy-state next' { Resolve-Baseline $null 'deploy/2026-10-01_01' $tags | Should Be 'deploy/2026-10-01_01' }
    It 'falls back to the newest tag' { Resolve-Baseline 'deploy/gone' $null $tags | Should Be 'deploy/2026-10-01_02' }
    It 'returns null on a first run' { Resolve-Baseline $null $null @() | Should BeNullOrEmpty }
}

Describe 'New-ReleaseReadme' {
    $r = Join-Path $TestDrive '2026-10-01'
    foreach ($b in @(@{ f = '01_1000'; n = 1 }, @{ f = '02_1400'; n = 2 })) {
        $d = Join-Path $r $b.f
        New-Item -ItemType Directory $d -Force | Out-Null
        $m = [ordered]@{ release = '2026-10-01'; build = $b.n; tag = "deploy/2026-10-01_0$($b.n)"; commit = ('a' * 40); dirty = $false; createdAt = '2026-10-01 10:00'; projects = @('OpenAccessBaseControls'); files = @(@{ path = 'SQL/001_a.sql' }) }
        ConvertTo-Json $m -Depth 4 | Set-Content (Join-Path $d 'manifest.json')
    }
    New-ReleaseReadme $r
    $text = Get-Content (Join-Path $r 'README.md') -Raw
    It 'lists builds newest first' { $text.IndexOf('02_1400') | Should BeLessThan $text.IndexOf('01_1000') }
    It 'shows the tag' { $text | Should Match 'deploy/2026-10-01_02' }
}

Describe 'Test-ModuleCreateFirst' {
    It 'accepts a module CREATE first, after comments' {
        Test-ModuleCreateFirst "-- header`r`n/* note */`r`nCREATE OR ALTER FUNCTION ckbcustom.f() RETURNS INT AS BEGIN RETURN 1 END" | Should Be $true
    }
    It 'rejects a DROP before the CREATE' {
        Test-ModuleCreateFirst "DROP FUNCTION IF EXISTS ckbcustom.f;`r`n`r`nCREATE FUNCTION ckbcustom.f() RETURNS INT AS BEGIN RETURN 1 END" | Should Be $false
    }
    It 'ignores scripts with no module' {
        Test-ModuleCreateFirst "IF OBJECT_ID('ckbcustom.t','U') IS NULL CREATE TABLE ckbcustom.t (x INT)" | Should Be $true
    }
}
