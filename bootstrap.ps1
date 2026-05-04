#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap the full TransportPlatform locally from scratch.

.DESCRIPTION
    1. Creates a TransportPlatform folder in the current directory
    2. Clones all service repos from GitHub (sezo)
    3. Starts shared infrastructure (Postgres, RabbitMQ, Keycloak, BaGet, Observability)
    4. Waits for BaGet to be ready, then builds & publishes NuGet packages
    5. Spins up all services (Ticketing, Accounting, Reporting, Gateway)

.PARAMETER GitHubUser
    GitHub username to clone repos from. Default: sezo

.PARAMETER BaGetApiKey
    API key configured in BaGet. Default: your-secret-key (matches infra docker-compose)

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

# ── Helpers ──────────────────────────────────────────────────────────────────

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

function Wait-Http([string]$url, [int]$timeoutSeconds = 120, [string]$label = $url) {
    Write-Host "    Waiting for $label to be ready..." -NoNewline
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if ($resp.StatusCode -lt 500) {
                Write-Host " ready!" -ForegroundColor Green
                return
            }
        } catch { }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 3
    }
    Write-Host " TIMEOUT" -ForegroundColor Red
    throw "Timed out waiting for $label ($url)"
}

function Wait-Tcp([string]$host, [int]$port, [int]$timeoutSeconds = 60, [string]$label = "") {
    if (-not $label) { $label = "${host}:${port}" }
    Write-Host "    Waiting for $label to be ready..." -NoNewline
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $result = Test-NetConnection -ComputerName $host -Port $port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
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

function Invoke-Step([string]$desc, [scriptblock]$block) {
    Write-Host "    $desc..." -NoNewline
    try {
        & $block | Out-Null
        Write-Host " done" -ForegroundColor Green
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        throw
    }
}

# ── Prerequisite checks ───────────────────────────────────────────────────────

Write-Step "Checking prerequisites"

foreach ($tool in @("git", "docker", "dotnet")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not found: $tool. Please install it and re-run."
    }
    Write-Ok "$tool found"
}

$dockerRunning = docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Docker daemon is not running. Start Docker Desktop and re-run."
}
Write-Ok "Docker daemon is running"

# ── Folder setup ──────────────────────────────────────────────────────────────

$root = Join-Path (Get-Location) "TransportPlatform"

Write-Step "Setting up TransportPlatform folder at $root"
if (-not (Test-Path $root)) {
    New-Item -ItemType Directory -Path $root | Out-Null
    Write-Ok "Created $root"
} else {
    Write-Warn "Folder already exists, continuing"
}

# ── Repos ─────────────────────────────────────────────────────────────────────

$repos = @(
    @{ name = "_transport-platform-meta";       gh = "transport-platform-meta" }
    @{ name = "TransportPlatform.Infrastructure"; gh = "TransportPlatform.Infrastructure" }
    @{ name = "TransportPlatform.Ticketing";     gh = "TransportPlatform.Ticketing" }
    @{ name = "TransportPlatform.Accounting";    gh = "TransportPlatform.Accounting" }
    @{ name = "TransportPlatform.Reporting";     gh = "TransportPlatform.Reporting" }
    @{ name = "TransportPlatform.Gateway";       gh = "TransportPlatform.Gateway" }
    @{ name = "TransportPlatform.BackofficeApp"; gh = "TransportPlatform.BackofficeApp" }
    @{ name = "TransportPlatform.MobileApp";     gh = "TransportPlatform.MobileApp" }
)

if (-not $SkipClone) {
    Write-Step "Cloning repositories from github.com/$GitHubUser"
    foreach ($repo in $repos) {
        $dest = Join-Path $root $repo.name
        if (Test-Path $dest) {
            Write-Warn "$($repo.name) already exists — pulling latest"
            Push-Location $dest
            git pull --ff-only 2>&1 | Out-Null
            Pop-Location
        } else {
            $url = "https://github.com/$GitHubUser/$($repo.gh).git"
            Write-Host "    Cloning $($repo.name)..."
            git clone $url $dest 2>&1 | Out-Null
            Write-Ok "Cloned $($repo.name)"
        }
    }
} else {
    Write-Warn "Skipping clone (-SkipClone)"
}

# ── Infrastructure ────────────────────────────────────────────────────────────

$infraDir = Join-Path $root "_transport-platform-meta\infra"

if (-not $SkipInfra) {
    Write-Step "Starting shared infrastructure (docker compose)"

    if (-not (Test-Path $infraDir)) {
        throw "Infra directory not found: $infraDir. Was the meta repo cloned?"
    }

    Push-Location $infraDir
    docker compose up -d 2>&1 | Out-Null
    Pop-Location
    Write-Ok "Infrastructure containers started"

    # Wait for all dependencies before proceeding

    # Postgres — one port per service DB (EF migrations run against these)
    Wait-Tcp "localhost" 5432 60 "Postgres / tickets     (5432)"
    Wait-Tcp "localhost" 5433 60 "Postgres / vehicles    (5433)"
    Wait-Tcp "localhost" 5434 60 "Postgres / accounting  (5434)"
    Wait-Tcp "localhost" 5435 60 "Postgres / reporting   (5435)"

    # RabbitMQ AMQP port
    Wait-Tcp "localhost" 5672 60 "RabbitMQ AMQP (5672)"

    # BaGet HTTP
    Wait-Http "http://localhost:5555/health" 120 "BaGet (5555)"

    # Keycloak takes the longest — poll its ready endpoint
    Write-Host "    Waiting for Keycloak (can take up to 2 min)..." -NoNewline
    $deadline = (Get-Date).AddSeconds(150)
    $keycloakReady = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:9090/health/ready" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($r.StatusCode -eq 200) { Write-Host " ready!" -ForegroundColor Green; $keycloakReady = $true; break }
        } catch { }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5
    }
    if (-not $keycloakReady) { Write-Warn "Keycloak did not report ready — services may fail to validate tokens" }
} else {
    Write-Warn "Skipping infrastructure (-SkipInfra)"
}

# ── NuGet packages ────────────────────────────────────────────────────────────

if (-not $SkipNuGet) {
    Write-Step "Building and publishing NuGet packages to BaGet"

    $infraSrc = Join-Path $root "TransportPlatform.Infrastructure\src"
    $nupkgOut  = Join-Path $root "_nupkgs"
    New-Item -ItemType Directory -Path $nupkgOut -Force | Out-Null

    $packages = @(
        "TransportPlatform.Contracts\TransportPlatform.Contracts.csproj"
        "TransportPlatform.Infrastructure.Common\TransportPlatform.Infrastructure.Common.csproj"
    )

    foreach ($pkg in $packages) {
        $csproj = Join-Path $infraSrc $pkg
        $pkgName = [System.IO.Path]::GetFileNameWithoutExtension($pkg.Split("\")[1])
        Write-Host "    Packing $pkgName..."
        dotnet pack $csproj -c Release -o $nupkgOut --no-restore 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # restore first then pack
            dotnet restore $csproj 2>&1 | Out-Null
            dotnet pack $csproj -c Release -o $nupkgOut 2>&1 | Out-Null
        }
        Write-Ok "Packed $pkgName"
    }

    # Push every .nupkg to BaGet
    Get-ChildItem -Path $nupkgOut -Filter "*.nupkg" | ForEach-Object {
        Write-Host "    Publishing $($_.Name) to BaGet..."
        dotnet nuget push $_.FullName `
            --source $BaGetUrl `
            --api-key $BaGetApiKey `
            --skip-duplicate 2>&1 | Out-Null
        Write-Ok "Published $($_.Name)"
    }
} else {
    Write-Warn "Skipping NuGet (-SkipNuGet)"
}

# ── Application services ──────────────────────────────────────────────────────

$services = @(
    @{ name = "Ticketing";  dir = "TransportPlatform.Ticketing"  }
    @{ name = "Accounting"; dir = "TransportPlatform.Accounting" }
    @{ name = "Reporting";  dir = "TransportPlatform.Reporting"  }
    @{ name = "Gateway";    dir = "TransportPlatform.Gateway"    }
)

if (-not $SkipServices) {
    Write-Step "Building and starting application services"
    Write-Warn "First run will be slow — Docker images are being built from source"

    foreach ($svc in $services) {
        $dir = Join-Path $root $svc.dir
        if (-not (Test-Path $dir)) {
            Write-Warn "$($svc.name) repo not found at $dir — skipping"
            continue
        }
        Write-Host "    Starting $($svc.name)..."
        Push-Location $dir
        docker compose up -d --build 2>&1 | Out-Null
        Pop-Location
        Write-Ok "$($svc.name) started"
    }

    Write-Step "Waiting for services to become healthy"
    $healthChecks = @(
        @{ url = "http://localhost:5001/swagger/v1/swagger.json"; label = "Ticketing (5001)" }
        @{ url = "http://localhost:5101/swagger/v1/swagger.json"; label = "Accounting (5101)" }
        @{ url = "http://localhost:5201/swagger/v1/swagger.json"; label = "Reporting (5201)" }
        @{ url = "http://localhost:8081/health";                  label = "Gateway Internal (8081)" }
    )

    foreach ($hc in $healthChecks) {
        try { Wait-Http $hc.url 90 $hc.label }
        catch { Write-Warn "$($hc.label) did not become ready in time — check docker logs" }
    }
} else {
    Write-Warn "Skipping services (-SkipServices)"
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "  TransportPlatform bootstrap complete!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
Write-Host "  Services" -ForegroundColor White
Write-Host "    Ticketing API       http://localhost:5001/swagger"
Write-Host "    Accounting API      http://localhost:5101/swagger"
Write-Host "    Reporting API       http://localhost:5201/swagger"
Write-Host "    Gateway Public      http://localhost:8080"
Write-Host "    Gateway Internal    http://localhost:8081"
Write-Host ""
Write-Host "  Infrastructure" -ForegroundColor White
Write-Host "    Keycloak Admin      http://localhost:9090  (admin / admin)"
Write-Host "    RabbitMQ UI         http://localhost:15672 (transport / transport)"
Write-Host "    Grafana             http://localhost:3000"
Write-Host "    BaGet               http://localhost:5555"
Write-Host ""
Write-Host "  Useful commands" -ForegroundColor White
Write-Host "    docker compose logs -f   (run inside a service folder)"
Write-Host "    .\bootstrap.ps1 -SkipClone -SkipInfra -SkipNuGet   (restart services only)"
Write-Host ""
