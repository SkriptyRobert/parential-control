# Install AdGuard Home using Docker
# Requires administrator privileges and Docker Desktop installed

param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = $PSScriptRoot
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n=== Installing AdGuard Home ===" -ForegroundColor Cyan

# Check Docker
$dockerInstalled = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerInstalled) {
    Write-Error "Docker is not installed! Please install Docker Desktop from https://www.docker.com/products/docker-desktop"
    exit 1
}

# Check if Docker is running
try {
    docker ps | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker is not running! Please start Docker Desktop."
        exit 1
    }
} catch {
    Write-Error "Docker is not running! Please start Docker Desktop."
    exit 1
}

# Create configuration directories
$workDir = Join-Path $ProjectPath "adguard-config\work"
$confDir = Join-Path $ProjectPath "adguard-config\conf"

if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    Write-Host "Created directory: $workDir" -ForegroundColor Green
}

if (-not (Test-Path $confDir)) {
    New-Item -ItemType Directory -Path $confDir -Force | Out-Null
    Write-Host "Created directory: $confDir" -ForegroundColor Green
}

# Check docker-compose.yml
$dockerComposeFile = Join-Path $ProjectPath "docker-compose.yml"
if (-not (Test-Path $dockerComposeFile)) {
    Write-Error "File docker-compose.yml not found in: $ProjectPath"
    exit 1
}

# Stop existing container
Write-Host "`nStopping existing container (if any)..." -ForegroundColor Yellow
docker-compose -f $dockerComposeFile down 2>$null

# Start AdGuard Home
Write-Host "`nStarting AdGuard Home..." -ForegroundColor Yellow
Set-Location $ProjectPath
docker-compose up -d

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nAdGuard Home started successfully!" -ForegroundColor Green
    Write-Host "`nWeb interface: http://localhost:3000" -ForegroundColor Cyan
    Write-Host "DNS server: 127.0.0.1:53" -ForegroundColor Cyan
    Write-Host "`nNote: On first run you will need to complete setup via web interface." -ForegroundColor Yellow
    Write-Host "Then set DNS on this PC to 127.0.0.1" -ForegroundColor Yellow
} else {
    Write-Error "Error starting AdGuard Home!"
    exit 1
}
