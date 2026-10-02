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
    # Type or Types: CXFloatingShelf keeps its table type in SQL/Type/.
    if ($path -match '[\\/]Types?[\\/]') { return 0 }
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

# --- client.json ---
# Every key is optional, and the defaults are the lists the build script used
# before client.json existed, so a repo without them packages exactly as before.

function Get-DefaultWebDlls {
    @(
        '^CX\.',
        '^Cantactix\.OpenAccess\.Automator\.',
        '^(ClosedXML|DocumentFormat\.OpenXml|ExcelDataReader|ExcelNumberFormat|RBush|SixLabors\.Fonts|System\.IO\.Packaging|Dapper)\.'
    )
}

# Vendor assemblies the web tier needs but OA does not ship. BCAE comes with
# the batch (Publishing Server) install, so a web server has no copy; both files
# are needed because BCAEJobGateway loads its own resources assembly.
function Get-DefaultVendorWebDlls { @('JDA.Intactix.BCAE.dll', 'JDA.Intactix.BCAE.Resources.dll') }

function Read-ClientConfig([string]$RepoRoot) {
    $path = Join-Path $RepoRoot 'client.json'
    $data = $null
    if (Test-Path $path) { $data = Get-Content $path -Raw | ConvertFrom-Json }
    $has = { param($key) $data -and $data.PSObject.Properties[$key] -and $null -ne $data.$key }
    return [PSCustomObject]@{
        # @() outside $(): a one-item list would otherwise unroll to a scalar.
        projects       = @($(if (& $has 'projects') { $data.projects }))
        webDlls        = @($(if (& $has 'webDlls') { $data.webDlls } else { Get-DefaultWebDlls }))
        vendorWebDlls  = @($(if (& $has 'vendorWebDlls') { $data.vendorWebDlls } else { Get-DefaultVendorWebDlls }))
        vendorExplicit = [bool](& $has 'vendorWebDlls')
        targets        = $(if (& $has 'targets') { $data.targets } else { $null })
    }
}

function Get-ClientProject($Config, [string]$Name) {
    @($Config.projects) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

# Folder of a project relative to the repo, forward slashes. client.json path
# wins; a project not listed is a folder of the same name (the old convention).
function Get-ProjectRelPath($Config, [string]$Name) {
    $p = Get-ClientProject $Config $Name
    $rel = if ($p -and $p.path) { [string]$p.path } else { $Name }
    return ($rel -replace '\\', '/').TrimEnd('/')
}

function Resolve-ProjectPath([string]$RepoRoot, $Config, [string]$Name) {
    Join-Path $RepoRoot ((Get-ProjectRelPath $Config $Name) -replace '/', '\')
}

# --- Deploy targets ---
# Where a target type deploys: 'web' | 'batch' | 'sapro', for 'saas' or
# 'local'. A batch or SA Pro project's deployTo wins on SaaS; web projects share
# one Open Access tree, so they always use targets.web.

function Get-DeployTarget($Config, [string]$Kind, [string]$Mode = 'saas', [string]$ProjectName) {
    if ($ProjectName -and $Kind -ne 'web' -and $Mode -eq 'saas') {
        $p = Get-ClientProject $Config $ProjectName
        if ($p -and $p.PSObject.Properties['deployTo'] -and $p.deployTo) { return [string]$p.deployTo }
    }
    $t = $Config.targets
    if ($t -and $t.PSObject.Properties[$Kind]) {
        $entry = $t.$Kind
        if ($entry.PSObject.Properties[$Mode] -and $entry.$Mode) { return [string]$entry.$Mode }
    }
    if ($Mode -ne 'saas') { return $null }
    $defaults = @{ web = 'U:\OpenAccess\Customization'; batch = 'F:\batch\exe'; sapro = $null }
    return $defaults[$Kind]
}

# --- Web DLLs ---
# Vendor DLLs are let through by name; everything else that OA or the
# framework already ships is refused before the allowlist is consulted.

function Test-WebDll([string]$FileName, [string[]]$Rules, [string[]]$Vendor) {
    if ($FileName -notmatch '\.dll$' -or $FileName -match '\.vshost\.') { return $false }
    if ($Vendor -contains $FileName) { return $true }
    if ($FileName -match 'Serilog|PlanogramUpdater|^JDA\.|^Microsoft\.|^System\.|^Newtonsoft\.|^Azure\.') { return $false }
    foreach ($r in $Rules) { if ($FileName -match $r) { return $true } }
    return $false
}

# A vendor DLL from the project's build output, else its Libraries folder
# (Blackhawk keeps JDA.Intactix.BCAE.Resources.dll only in Libraries).
function Find-VendorDll([string]$ProjectRoot, [string]$FileName) {
    foreach ($dir in @('bin\Release', 'bin', 'Libraries')) {
        $p = Join-Path $ProjectRoot (Join-Path $dir $FileName)
        if (Test-Path $p) { return $p }
    }
    return $null
}

# --- Releases and builds ---
# A release is the date it was started; builds inside it are NN_HHmm.

function Get-NextBuild([string]$ReleaseDir) {
    if (-not (Test-Path $ReleaseDir)) { return 1 }
    $nums = @(Get-ChildItem $ReleaseDir -Directory |
        Where-Object { $_.Name -match '^\d{2}_\d{4}$' } |
        ForEach-Object { [int]$_.Name.Substring(0, 2) })
    if ($nums.Count -eq 0) { return 1 }
    return [int](($nums | Measure-Object -Maximum).Maximum) + 1
}

function Get-BuildTag([string]$Release, [int]$Build) { 'deploy/{0}_{1:D2}' -f $Release, $Build }

# Baseline for "Changes since baseline": the request's, else deploy-state's,
# else the newest deploy tag. $null means a first run.
function Resolve-Baseline([string]$Requested, [string]$StateTag, [string[]]$Tags) {
    $Tags = @($Tags | Where-Object { $_ })
    foreach ($c in @($Requested, $StateTag)) {
        if ($c -and ($Tags -contains $c)) { return $c }
    }
    if ($Tags.Count -gt 0) { return $Tags[0] }
    return $null
}

# Release README: every build in the release, newest first, from each build's
# manifest.json. Rewritten after every build.
function New-ReleaseReadme([string]$ReleaseDir) {
    $builds = @(Get-ChildItem $ReleaseDir -Directory |
        Where-Object { $_.Name -match '^\d{2}_\d{4}$' } |
        Sort-Object Name -Descending)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Release $(Split-Path $ReleaseDir -Leaf)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Builds newest first. To undo, roll back newest first: run `Backup\<time>\Rollback.ps1` in each deployed build folder on the batch server.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Build | Packaged | Tag | Commit | Projects | SQL files |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|')
    foreach ($b in $builds) {
        $mp = Join-Path $b.FullName 'manifest.json'
        if (-not (Test-Path $mp)) {
            [void]$sb.AppendLine("| ``$($b.Name)`` | - | - | - | (no manifest) | - |")
            continue
        }
        $m = Get-Content $mp -Raw | ConvertFrom-Json
        $sha = if ($m.commit) { ([string]$m.commit).Substring(0, 7) } else { '-' }
        if ($m.dirty) { $sha += ' (uncommitted changes)' }
        [void]$sb.AppendLine("| [``$($b.Name)``]($($b.Name)/README.md) | $($m.createdAt) | ``$($m.tag)`` | ``$sha`` | $(@($m.projects) -join ', ') | $(@($m.files).Count) |")
    }
    [IO.File]::WriteAllText((Join-Path $ReleaseDir 'README.md'), $sb.ToString(), [Text.Encoding]::UTF8)
}
