# Uninstall AdGuard Home Docker Container
# Requires administrator privileges

param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = $PSScriptRoot,
    
    [Parameter(Mandatory=$false)]
    [switch]$RemoveData
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  AdGuard Home - Docker Uninstall" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if container exists
$containerExists = docker ps -a --filter "name=adguard-home" --format "{{.Names}}" 2>$null
if (-not $containerExists) {
    Write-Host "AdGuard Home container not found." -ForegroundColor Yellow
    exit 0
}

# Stop and remove container
Write-Host "Stopping and removing container..." -ForegroundColor Yellow
Push-Location $ProjectPath

docker-compose down 2>$null
if ($?) {
    Write-Host "  Container stopped and removed" -ForegroundColor Green
}

# Remove data if requested
if ($RemoveData) {
    $configDir = Join-Path $ProjectPath "config"
    if (Test-Path $configDir) {
        Write-Host "Removing configuration data..." -ForegroundColor Yellow
        Remove-Item -Path $configDir -Recurse -Force
        Write-Host "  Configuration data removed" -ForegroundColor Green
    }
}

# Remove firewall rules
Write-Host "Removing firewall rules..." -ForegroundColor Yellow
$rules = Get-NetFirewallRule -DisplayName "AdGuard*" -ErrorAction SilentlyContinue
if ($rules) {
    $rules | Remove-NetFirewallRule
    Write-Host "  Firewall rules removed" -ForegroundColor Green
} else {
    Write-Host "  No firewall rules found" -ForegroundColor Gray
}

Pop-Location

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Uninstall Complete" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Note: Remember to reset DNS settings on this PC." -ForegroundColor Yellow

