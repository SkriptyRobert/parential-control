# Install AdGuard Home using Docker
# Requires administrator privileges and Docker Desktop installed
#
# Usage: .\install-docker-adguard.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = $PSScriptRoot
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    Write-Host "Run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  AdGuard Home - Docker Installation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check Docker installation
$dockerInstalled = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerInstalled) {
    Write-Host "Docker is not installed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Installation options:" -ForegroundColor Yellow
    Write-Host "  1. Download from: https://www.docker.com/products/docker-desktop" -ForegroundColor White
    Write-Host "  2. Or use winget: winget install Docker.DockerDesktop" -ForegroundColor White
    Write-Host ""
    Write-Host "After installation, restart your PC and run this script again." -ForegroundColor Yellow
    exit 1
}

# Check if Docker is running
Write-Host "Checking Docker status..." -ForegroundColor Yellow
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker daemon not running"
    }
    Write-Host "  Docker is running" -ForegroundColor Green
} catch {
    Write-Host "Docker is not running!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please start Docker Desktop and wait for it to initialize." -ForegroundColor Yellow
    Write-Host "Look for the Docker icon in the system tray." -ForegroundColor Yellow
    exit 1
}

# Create configuration directories
$configDir = Join-Path $ProjectPath "config"
$workDir = Join-Path $configDir "work"
$confDir = Join-Path $configDir "conf"

if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    Write-Host "Created directory: $workDir" -ForegroundColor Green
}

if (-not (Test-Path $confDir)) {
    New-Item -ItemType Directory -Path $confDir -Force | Out-Null
    Write-Host "Created directory: $confDir" -ForegroundColor Green
}

# Copy pre-configured AdGuardHome.yaml if exists
$parentConfigPath = Join-Path (Split-Path $ProjectPath -Parent) "config\AdGuardHome.yaml"
$targetConfigPath = Join-Path $confDir "AdGuardHome.yaml"

if ((Test-Path $parentConfigPath) -and -not (Test-Path $targetConfigPath)) {
    Copy-Item -Path $parentConfigPath -Destination $targetConfigPath -Force
    Write-Host "Copied pre-configured AdGuardHome.yaml" -ForegroundColor Green
}

# Check docker-compose.yml
$dockerComposeFile = Join-Path $ProjectPath "docker-compose.yml"
if (-not (Test-Path $dockerComposeFile)) {
    Write-Error "File docker-compose.yml not found in: $ProjectPath"
    exit 1
}

# Stop existing container
Write-Host "`nStopping existing container (if any)..." -ForegroundColor Yellow
Push-Location $ProjectPath
docker-compose down 2>$null

# Start AdGuard Home
Write-Host "Starting AdGuard Home container..." -ForegroundColor Yellow
docker-compose up -d

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  Installation Complete" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    Write-Host "Container status:" -ForegroundColor Yellow
    docker ps --filter "name=adguard-home" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    Write-Host "`nWeb interface: http://localhost:3000" -ForegroundColor Cyan
    Write-Host "DNS server: 127.0.0.1:53" -ForegroundColor Cyan
    
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Open http://localhost:3000 in your browser" -ForegroundColor White
    Write-Host "  2. Complete the initial setup wizard" -ForegroundColor White
    Write-Host "  3. Set DNS on this PC to 127.0.0.1" -ForegroundColor White
    
    Write-Host "`nDocker commands:" -ForegroundColor Yellow
    Write-Host "  Start:   docker-compose up -d" -ForegroundColor White
    Write-Host "  Stop:    docker-compose down" -ForegroundColor White
    Write-Host "  Logs:    docker-compose logs -f" -ForegroundColor White
    Write-Host "  Restart: docker-compose restart" -ForegroundColor White
    
    Pop-Location
    exit 0
} else {
    Write-Error "Error starting AdGuard Home container!"
    Pop-Location
    exit 1
}

