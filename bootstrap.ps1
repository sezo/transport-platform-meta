#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap the full TransportPlatform locally from scratch.

.DESCRIPTION
    1. Creates a TransportPlatform folder in the current directory
    2. Clones all service repos from GitHub
    3. Starts shared infrastructure (Postgres, RabbitMQ, Keycloak, BaGet, Observability)
    4. Waits for every dependency (including Postgres TCP) to be ready
    5. Builds and publishes NuGet packages to BaGet
    6. Spins up all services (Ticketing, Accounting, Reporting, Gateway)

.PARAMETER GitHubUser
    GitHub username to clone repos from. Default: sezo

.PARAMETER BaGetApiKey
    API key configured in BaGet. Default: your-secret-key

.PARAMETER BaGetUrl
    NuGet v3 index URL for BaGet. Default: http://localhost:5555/v3/index.json

.PARAMETER SkipClone
    Skip cloning repos (useful when re-running on an existing setup)

.PARAMETER SkipInfra
    Skip starting infrastructure (useful when infra is already running)

.PARAMETER SkipNuGet
    Skip building and publishing NuGet packages

.PARAMETER SkipServices
    Skip spinning up application services

.EXAMPLE
    .\bootstrap.ps1
    .\bootstrap.ps1 -SkipClone -SkipInfra
    .\bootstrap.ps1 -GitHubUser myorg
#>

param(
    [string]$GitHubUser  = "sezo",
    [string]$BaGetApiKey = "your-secret-key",
    [string]$BaGetUrl    = "http://localhost:5555/v3/index.json",
    [switch]$SkipClone,
    [switch]$SkipInfra,
    [switch]$SkipNuGet,
    [switch]$SkipServices
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host "    [OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "    [!!] $msg" -ForegroundColor Yellow
}

function Wait-Http([string]$url, [int]$timeoutSeconds = 120, [string]$label = "") {
    if (-not $label) { $label = $url }
    Write-Host "    Waiting for $label ..." -NoNewline
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if ($resp.StatusCode -lt 500) {
                Write-Host " ready!" -ForegroundColor Green
                return
            }
        }
        catch { }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 3
    }
    Write-Host " TIMEOUT" -ForegroundColor Red
    throw "Timed out waiting for $label"
}

function Wait-Tcp([string]$computerName, [int]$port, [int]$timeoutSeconds = 60, [string]$label = "") {
    if (-not $label) { $label = "${computerName}:${port}" }
    Write-Host "    Waiting for $label ..." -NoNewline
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $result = Test-NetConnection -ComputerName $computerName -Port $port `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($result.TcpTestSucceeded) {
            Write-Host " ready!" -ForegroundColor Green
            return
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
    }
    Write-Host " TIMEOUT" -ForegroundColor Red
    throw "Timed out waiting for $label"
}

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

Write-Step "Checking prerequisites"

foreach ($tool in @("git", "docker", "dotnet")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not found: $tool. Please install it and re-run."
    }
    Write-Ok "$tool found"
}

docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Docker daemon is not running. Start Docker Desktop and re-run."
}
Write-Ok "Docker daemon is running"

# ---------------------------------------------------------------------------
# Folder setup
# ---------------------------------------------------------------------------

$root = Join-Path (Get-Location) "TransportPlatform"

Write-Step "Setting up TransportPlatform folder at $root"
if (-not (Test-Path $root)) {
    New-Item -ItemType Directory -Path $root | Out-Null
    Write-Ok "Created $root"
}
else {
    Write-Warn "Folder already exists, continuing"
}

# ---------------------------------------------------------------------------
# Clone repositories
# ---------------------------------------------------------------------------

$repos = @(
    @{ name = "_transport-platform-meta";        gh = "transport-platform-meta" },
    @{ name = "TransportPlatform.Infrastructure"; gh = "TransportPlatform.Infrastructure" },
    @{ name = "TransportPlatform.Ticketing";      gh = "TransportPlatform.Ticketing" },
    @{ name = "TransportPlatform.Accounting";     gh = "TransportPlatform.Accounting" },
    @{ name = "TransportPlatform.Reporting";      gh = "TransportPlatform.Reporting" },
    @{ name = "TransportPlatform.Gateway";        gh = "TransportPlatform.Gateway" },
    @{ name = "TransportPlatform.BackofficeApp";  gh = "TransportPlatform.BackofficeApp" },
    @{ name = "TransportPlatform.MobileApp";      gh = "TransportPlatform.MobileApp" }
)

if (-not $SkipClone) {
    Write-Step "Cloning repositories from github.com/$GitHubUser"
    foreach ($repo in $repos) {
        $dest = Join-Path $root $repo.name
        if (Test-Path $dest) {
            Write-Warn "$($repo.name) already exists -- pulling latest"
            Push-Location $dest
            git pull --ff-only | Out-Null
            Pop-Location
        }
        else {
            $cloneUrl = "https://github.com/$GitHubUser/$($repo.gh).git"
            Write-Host "    Cloning $($repo.name) ..."
            git clone $cloneUrl $dest | Out-Null
            Write-Ok "Cloned $($repo.name)"
        }
    }
}
else {
    Write-Warn "Skipping clone (-SkipClone)"
}

# ---------------------------------------------------------------------------
# Infrastructure
# ---------------------------------------------------------------------------

$infraDir = Join-Path $root "_transport-platform-meta\infra"

if (-not $SkipInfra) {
    Write-Step "Starting shared infrastructure"

    if (-not (Test-Path $infraDir)) {
        throw "Infra directory not found: $infraDir. Was the meta repo cloned?"
    }

    Push-Location $infraDir
    docker compose up -d | Out-Null
    Pop-Location
    Write-Ok "Infrastructure containers started"

    # Postgres -- one port per service DB, EF migrations depend on these
    Wait-Tcp "localhost" 5432 60 "Postgres/tickets    (5432)"
    Wait-Tcp "localhost" 5433 60 "Postgres/vehicles   (5433)"
    Wait-Tcp "localhost" 5434 60 "Postgres/accounting (5434)"
    Wait-Tcp "localhost" 5435 60 "Postgres/reporting  (5435)"

    # RabbitMQ AMQP
    Wait-Tcp "localhost" 5672 60 "RabbitMQ AMQP (5672)"

    # BaGet -- no /health endpoint; poll the NuGet v3 index instead
    Wait-Http "http://localhost:5555/v3/index.json" 120 "BaGet (5555)"

    # Keycloak takes the longest
    Write-Host "    Waiting for Keycloak (up to 2 min) ..." -NoNewline
    $deadline      = (Get-Date).AddSeconds(150)
    $keycloakReady = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:9090/health/ready" `
                    -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($r.StatusCode -eq 200) {
                Write-Host " ready!" -ForegroundColor Green
                $keycloakReady = $true
                break
            }
        }
        catch { }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5
    }
    if (-not $keycloakReady) {
        Write-Warn "Keycloak did not report ready -- services may fail to validate tokens"
    }
}
else {
    Write-Warn "Skipping infrastructure (-SkipInfra)"
}

# ---------------------------------------------------------------------------
# NuGet packages
# ---------------------------------------------------------------------------

if (-not $SkipNuGet) {
    Write-Step "Building and publishing NuGet packages to BaGet"

    $infraSrc = Join-Path $root "TransportPlatform.Infrastructure\src"
    $nupkgOut = Join-Path $root "_nupkgs"
    New-Item -ItemType Directory -Path $nupkgOut -Force | Out-Null

    $packages = @(
        "TransportPlatform.Contracts\TransportPlatform.Contracts.csproj",
        "TransportPlatform.Infrastructure.Common\TransportPlatform.Infrastructure.Common.csproj"
    )

    foreach ($pkg in $packages) {
        $csproj  = Join-Path $infraSrc $pkg
        $pkgName = [System.IO.Path]::GetFileNameWithoutExtension(($pkg -split "\\")[1])
        Write-Host "    Packing $pkgName ..."
        dotnet pack $csproj -c Release -o $nupkgOut --no-restore | Out-Null
        if ($LASTEXITCODE -ne 0) {
            dotnet restore $csproj | Out-Null
            dotnet pack $csproj -c Release -o $nupkgOut | Out-Null
        }
        Write-Ok "Packed $pkgName"
    }

    Get-ChildItem -Path $nupkgOut -Filter "*.nupkg" | ForEach-Object {
        Write-Host "    Publishing $($_.Name) ..."
        dotnet nuget push $_.FullName `
            --source $BaGetUrl `
            --api-key $BaGetApiKey `
            --skip-duplicate | Out-Null
        Write-Ok "Published $($_.Name)"
    }
}
else {
    Write-Warn "Skipping NuGet (-SkipNuGet)"
}

# ---------------------------------------------------------------------------
# Application services
# ---------------------------------------------------------------------------

$services = @(
    @{ name = "Ticketing";      dir = "TransportPlatform.Ticketing" },
    @{ name = "Accounting";     dir = "TransportPlatform.Accounting" },
    @{ name = "Reporting";      dir = "TransportPlatform.Reporting" },
    @{ name = "Gateway";        dir = "TransportPlatform.Gateway" },
    @{ name = "BackofficeApp";  dir = "TransportPlatform.BackofficeApp" }
)

if (-not $SkipServices) {
    Write-Step "Building and starting application services (first run builds Docker images)"

    foreach ($svc in $services) {
        $svcDir = Join-Path $root $svc.dir
        if (-not (Test-Path $svcDir)) {
            Write-Warn "$($svc.name) repo not found at $svcDir -- skipping"
            continue
        }
        Write-Host "    Building and starting $($svc.name) ..."
        Push-Location $svcDir
        docker compose up -d --build
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "$($svc.name) failed to build or start. Check the output above."
        }
        Pop-Location
        Write-Ok "$($svc.name) started"
    }

    Write-Step "Waiting for services to become healthy"

    $healthChecks = @(
        @{ url = "http://localhost:5001/health"; label = "Ticketing    (5001)" },
        @{ url = "http://localhost:5101/health"; label = "Accounting   (5101)" },
        @{ url = "http://localhost:5201/health"; label = "Reporting    (5201)" },
        @{ url = "http://localhost:8081/health"; label = "Gateway      (8081)" },
        @{ url = "http://localhost:4200";        label = "Backoffice   (4200)" }
    )

    foreach ($hc in $healthChecks) {
        try {
            Wait-Http $hc.url 90 $hc.label
        }
        catch {
            Write-Warn "$($hc.label) did not become ready in time -- check: docker logs <container>"
        }
    }
}
else {
    Write-Warn "Skipping services (-SkipServices)"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "-----------------------------------------------------------" -ForegroundColor Green
Write-Host "  TransportPlatform bootstrap complete!" -ForegroundColor Green
Write-Host "-----------------------------------------------------------" -ForegroundColor Green
Write-Host ""
Write-Host "  Services" -ForegroundColor White
Write-Host "    Backoffice       http://localhost:4200"
Write-Host "    Ticketing API    http://localhost:5001/swagger"
Write-Host "    Accounting API   http://localhost:5101/swagger"
Write-Host "    Reporting API    http://localhost:5201/swagger"
Write-Host "    Gateway Public   http://localhost:8080"
Write-Host "    Gateway Internal http://localhost:8081"
Write-Host ""
Write-Host "  Infrastructure" -ForegroundColor White
Write-Host "    Keycloak Admin   http://localhost:9090  (admin / admin)"
Write-Host "    RabbitMQ UI      http://localhost:15672 (transport / transport)"
Write-Host "    Grafana          http://localhost:3000"
Write-Host "    BaGet            http://localhost:5555"
Write-Host ""
Write-Host "  Re-run flags" -ForegroundColor White
Write-Host "    -SkipClone      don't clone/pull repos"
Write-Host "    -SkipInfra      don't start infra containers"
Write-Host "    -SkipNuGet      don't build/push NuGet packages"
Write-Host "    -SkipServices   don't start service containers"
Write-Host ""
