# deploy-watcher.ps1 - Deployment Portal watcher (local deploys).
# Run from the client repo root, elevated when the copy scripts write to
# Program Files:
#   powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\source\repos\SkillsOfTheKraken\portal\deploy-watcher.ps1" -RepoRoot .
param([string]$RepoRoot = (Get-Location).Path)

$root = (Resolve-Path $RepoRoot).Path
. (Join-Path $PSScriptRoot '..\skills\create-saas-deployment-package\scripts\PackageLib.ps1')
$requestFile = Join-Path $root "_deploy-request.json"
$statusFile  = Join-Path $root "_deploy-status.json"
$historyPath = Join-Path $root "deploy-history.json"

# =============================================================================
# Helpers
# =============================================================================

function Write-Status([string]$project, [string]$requestId, [string]$status, [string]$message) {
    $obj = [ordered]@{
        project      = $project
        requestId    = $requestId
        status       = $status
        message      = $message
        completedAt  = (Get-Date -Format "o")
        watcherAlive = (Get-Date -Format "o")
    }
    $obj | ConvertTo-Json | Set-Content $statusFile -Encoding UTF8
}

function Update-Alive {
    if (Test-Path $statusFile) {
        try {
            $s = Get-Content $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $obj = [ordered]@{
                project      = $s.project
                requestId    = $s.requestId
                status       = $s.status
                message      = $s.message
                completedAt  = $s.completedAt
                watcherAlive = (Get-Date -Format "o")
            }
            $obj | ConvertTo-Json | Set-Content $statusFile -Encoding UTF8
        } catch { }
    } else {
        $obj = [ordered]@{
            project      = ""
            requestId    = ""
            status       = "idle"
            message      = "Watcher ready."
            completedAt  = ""
            watcherAlive = (Get-Date -Format "o")
        }
        $obj | ConvertTo-Json | Set-Content $statusFile -Encoding UTF8
    }
}

function Find-MSBuild {
    $msbuild = (Get-Command msbuild -ErrorAction SilentlyContinue).Source
    if ($msbuild) { return $msbuild }
    $candidates = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\msbuild.exe"
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Get-GitSha {
    try { return (git rev-parse HEAD 2>$null).Trim() } catch { return "" }
}

function Update-History([string]$projectName, [string]$env, [string]$deployType) {
    try {
        if (Test-Path $historyPath) {
            $raw = Get-Content $historyPath -Raw | ConvertFrom-Json
            if ($raw.PSObject.Properties["entries"]) {
                $history = $raw
            } else {
                $history = [PSCustomObject]@{ entries = @() }
            }
        } else {
            $history = [PSCustomObject]@{ entries = @() }
        }
        $entry = [PSCustomObject]@{
            project    = $projectName
            timestamp  = (Get-Date -Format "o")
            env        = $env
            deployType = $deployType
            gitSha     = (Get-GitSha)
        }
        $history.entries = @($history.entries) + $entry
        if ($history.entries.Count -gt 50) {
            $history.entries = $history.entries | Select-Object -Last 50
        }
        $history | ConvertTo-Json -Depth 3 | Set-Content $historyPath -Encoding UTF8
    } catch {
        Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] History update failed: " + $_.Exception.Message)
    }
}

function Write-GitStatus {
    $gitStatusPath = Join-Path $root "_git-status.json"
    try {
        $currentSha = Get-GitSha
        if (-not $currentSha) { return }

        $clientPath = Join-Path $root "client.json"
        if (-not (Test-Path $clientPath)) { return }
        $client = Get-Content $clientPath -Raw | ConvertFrom-Json

        $history = if (Test-Path $historyPath) {
            $raw = Get-Content $historyPath -Raw | ConvertFrom-Json
            if ($raw.PSObject.Properties["entries"]) { $raw } else { [PSCustomObject]@{ entries = @() } }
        } else { [PSCustomObject]@{ entries = @() } }

        $projects = [ordered]@{}
        foreach ($proj in $client.projects) {
            if ($proj.target -eq "skip" -or $null -eq $proj.target) { continue }

            $lastEntry = $history.entries |
                Where-Object { $_.project -eq $proj.name -and $_.PSObject.Properties["gitSha"] -and $_.gitSha } |
                Sort-Object timestamp | Select-Object -Last 1

            $lastSha = if ($lastEntry) { $lastEntry.gitSha } else { $null }

            $commitsSince = 0
            if ($lastSha -and $lastSha -ne $currentSha) {
                $logOut = git log --oneline "$lastSha..HEAD" -- $proj.path 2>$null
                $commitsSince = if ($logOut) { @($logOut).Count } else { 0 }
            }

            $uncommittedOut = git status --porcelain -- $proj.path 2>$null
            $hasUncommitted = [bool]($uncommittedOut -and @($uncommittedOut).Count -gt 0)

            $projects[$proj.name] = [ordered]@{
                commitsSince    = $commitsSince
                hasUncommitted  = $hasUncommitted
                lastDeployedSha = $lastSha
                currentSha      = $currentSha
            }
        }

        $out = [ordered]@{
            generatedAt = (Get-Date -Format "o")
            currentSha  = $currentSha
            projects    = $projects
        }
        $out | ConvertTo-Json -Depth 4 | Set-Content $gitStatusPath -Encoding UTF8
    } catch {
        Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] Write-GitStatus failed: " + $_.Exception.Message)
    }
}

# =============================================================================
# Deploy action
# =============================================================================

function Deploy-Project(
    [string]$projectName,
    [string]$requestId,
    [string]$env,
    [string]$deployType,
    [string]$webTarget,
    [string]$batchTarget
) {
    Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] Deploying $projectName (env=$env type=$deployType)...")

    $clientPath = Join-Path $root "client.json"
    if (-not (Test-Path $clientPath)) {
        Write-Status $projectName $requestId "failed" "client.json not found in repo root."
        return
    }

    $client = Get-Content $clientPath -Raw | ConvertFrom-Json
    $proj   = $client.projects | Where-Object { $_.name -eq $projectName } | Select-Object -First 1
    $cfg    = Read-ClientConfig $root

    if (-not $proj) {
        Write-Status $projectName $requestId "failed" "Project '$projectName' not found in client.json."
        return
    }
    if ($proj.target -eq "skip" -or $proj.target -eq $null) {
        Write-Status $projectName $requestId "failed" "Project '$projectName' is marked skip - not deployable."
        return
    }

    $folder = Join-Path $root $proj.path
    if (-not (Test-Path $folder)) {
        Write-Status $projectName $requestId "failed" "Project folder not found: $folder"
        return
    }

    $csproj = Get-ChildItem $folder -Filter "*.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $csproj) {
        Write-Status $projectName $requestId "failed" "No .csproj found in $folder"
        return
    }

    $msbuild = Find-MSBuild
    if (-not $msbuild) {
        Write-Status $projectName $requestId "failed" "msbuild not found. Open from VS 2022 Developer PowerShell."
        return
    }

    Write-Status $projectName $requestId "deploying" ("Building " + $csproj.Name + "...")
    Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] Building " + $csproj.Name + "...")
    & $msbuild $csproj.FullName /p:Configuration=Release /v:minimal /nologo 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Status $projectName $requestId "failed" ("Build FAILED (exit " + $LASTEXITCODE + ")")
        return
    }
    Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] Build OK")

    # Local locations from client.json targets.<kind>.local, else the request.
    $copyScript = if ($proj.PSObject.Properties['copyScript'] -and $proj.copyScript) { $proj.copyScript } else { $null }
    if ($proj.target -eq "web") {
        $deployDest = Get-DeployTarget $cfg 'web' 'local'
        if (-not $deployDest) { $deployDest = $webTarget }
        $batFile = Join-Path $folder $(if ($copyScript) { $copyScript } else { "CopyWebUI.bat" })
    } elseif ($proj.target -eq "batch") {
        $base = Get-DeployTarget $cfg 'batch' 'local'
        $deployDest = if ($base) { $base + "\" + $projectName } else { $batchTarget + "\" + $projectName }
        $batFile = Join-Path $folder $(if ($copyScript) { $copyScript } else { "CopyBatch.bat" })
    } elseif ($proj.target -eq "sapro") {
        $deployDest = Get-DeployTarget $cfg 'sapro' 'local'
        if (-not $deployDest) {
            Write-Status $projectName $requestId "failed" "No local SA Pro location (client.json targets.sapro.local)."
            return
        }
        $batFile = $null
    } else {
        Write-Status $projectName $requestId "failed" ("Unknown target type: " + $proj.target)
        return
    }

    if ($batFile -and -not (Test-Path $batFile)) {
        Write-Status $projectName $requestId "failed" ((Split-Path $batFile -Leaf) + " not found in $folder")
        return
    }

    Write-Status $projectName $requestId "deploying" ("Copying files to " + $deployDest + "...")
    Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] Deploying to $deployDest...")
    if ($batFile) {
        $env:DEPLOY_TARGET = $deployDest
        $output = & cmd.exe /c "`"$batFile`"" 2>&1
        $exit   = $LASTEXITCODE
        Remove-Item Env:DEPLOY_TARGET -ErrorAction SilentlyContinue
        $output | ForEach-Object { Write-Host "  $_" }
        if ($exit -ne 0) {
            Write-Status $projectName $requestId "failed" ("Deploy bat FAILED (exit " + $exit + ")")
            return
        }
    } else {
        # SA Pro: the built script DLL and its built config, flat.
        $projXml = [xml](Get-Content $csproj.FullName -Raw)
        $asm = $projXml.Project.PropertyGroup | Where-Object { $_.AssemblyName } | Select-Object -First 1 | ForEach-Object { $_.AssemblyName }
        if (-not $asm) { $asm = [IO.Path]::GetFileNameWithoutExtension($csproj.Name) }
        $bin = Join-Path $folder "bin\Release"
        if (-not (Test-Path (Join-Path $bin "$asm.dll"))) {
            Write-Status $projectName $requestId "failed" "$asm.dll not found in $bin"
            return
        }
        if (-not (Test-Path $deployDest)) { New-Item -ItemType Directory -Force $deployDest | Out-Null }
        Copy-Item (Join-Path $bin "$asm.dll") $deployDest -Force
        if (Test-Path (Join-Path $bin "$asm.dll.config")) { Copy-Item (Join-Path $bin "$asm.dll.config") $deployDest -Force }
    }

    # -- Deploy SQL (Types first, then Stored Procedures) ---------------------
    $sqlcmd = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
    if (-not $sqlcmd) {
        $candidate = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn\SQLCMD.EXE"
        if (Test-Path $candidate) { $sqlcmd = $candidate }
    }

    $envConfigPath = Join-Path $root "Environment Details\env-config.json"
    $dbServer = $null; $dbName = $null; $dbUser = $null; $dbPass = $null
    if (Test-Path $envConfigPath) {
        $envCfg = Get-Content $envConfigPath -Raw | ConvertFrom-Json
        if ($env -and $envCfg.PSObject.Properties[$env]) {
            $e = $envCfg.$env
            $dbServer = $e.Server; $dbName = $e.Database; $dbUser = $e.User; $dbPass = $e.Password
        }
    }

    if ($sqlcmd -and $dbServer -and $dbName) {
        Write-Status $projectName $requestId "deploying" "Deploying SQL objects..."
        $sqlRoot = Join-Path $folder "SQL"
        $sqlFiles = @()
        if (Test-Path $sqlRoot) {
            $sqlFiles = @(Get-ChildItem $sqlRoot -Recurse -Filter "*.sql" -File |
                Where-Object { $_.FullName -notmatch '\\Tests\\|\\Test Data\\|\\Old procs\\|\\Manual Scripts\\|\\Manual\\' } |
                Sort-Object @{ Expression = { Get-Tier $_.FullName } }, FullName)
        }
        $sqlFailed = $false
        foreach ($sqlFile in $sqlFiles) {
            Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] SQL: " + $sqlFile.Name)
            if ($dbUser -and $dbPass) {
                & $sqlcmd -S $dbServer -d $dbName -U $dbUser -P $dbPass -i $sqlFile.FullName -b 2>&1 | ForEach-Object { Write-Host "  $_" }
            } else {
                & $sqlcmd -S $dbServer -d $dbName -E -i $sqlFile.FullName -b 2>&1 | ForEach-Object { Write-Host "  $_" }
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] SQL FAILED: " + $sqlFile.Name)
                $sqlFailed = $true
            }
        }
        if ($sqlFailed) {
            Write-Status $projectName $requestId "failed" "SQL deployment failed - check output above."
            return
        }
    } elseif (-not $sqlcmd) {
        Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] SQL deploy skipped - sqlcmd not found.")
    } elseif (-not $dbServer) {
        Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] SQL deploy skipped - DB server not configured for '$env'.")
    }

    Update-History $projectName $env $deployType
    Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] $projectName OK")
    Write-Status $projectName $requestId "success" ("Built and deployed to " + $deployDest)
}

# =============================================================================
# Main loop
# =============================================================================

Write-Host "============================================"
Write-Host " Deployment Portal Watcher v2.0"
Write-Host " Repo root : $root"
Write-Host " Request   : $requestFile"
Write-Host " Status    : $statusFile"
Write-Host " Press Ctrl+C to stop."
Write-Host "============================================"

Update-Alive
Write-GitStatus

$_tick = 0
while ($true) {
    Start-Sleep 2
    Update-Alive
    $_tick++
    if ($_tick % 5 -eq 0) { Write-GitStatus }

    if (-not (Test-Path $requestFile)) { continue }

    try {
        $raw = Get-Content $requestFile -Raw -Encoding UTF8
        Remove-Item $requestFile -Force
        $req = $raw | ConvertFrom-Json

        if (-not $req.project -or -not $req.requestId) {
            Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] Malformed request - skipping.")
            continue
        }

        Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] Request: " + $req.project + " [" + $req.requestId + "]")

        if ($req.environment) { $env_val = $req.environment } else { $env_val = "" }
        if ($req.deployType)  { $type_val = $req.deployType  } else { $type_val = "Local" }
        if ($req.webTarget)   { $web_val = $req.webTarget    } else { $web_val = "C:\Program Files (x86)\JDA\Intactix\Intactix Knowledge Base\Open Access" }
        if ($req.batchTarget) { $batch_val = $req.batchTarget } else { $batch_val = "" }

        Deploy-Project `
            -projectName $req.project `
            -requestId   $req.requestId `
            -env         $env_val `
            -deployType  $type_val `
            -webTarget   $web_val `
            -batchTarget $batch_val
    } catch {
        Write-Host ("[" + (Get-Date -f "HH:mm:ss") + "] Error processing request: " + $_.Exception.Message)
    }
}
