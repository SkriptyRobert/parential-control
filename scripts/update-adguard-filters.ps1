# Update AdGuard Home Filters
# Updates configuration with latest filters from config/AdGuardHome.yaml
#
# Usage:
#   .\update-adguard-filters.ps1
#   .\update-adguard-filters.ps1 -RestartService

param(
    [Parameter(Mandatory=$false)]
    [switch]$RestartService
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Update AdGuard Home Filters" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Find AdGuard Home installation
$adguardService = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
if (-not $adguardService) {
    Write-Error "AdGuard Home service not found!"
    Write-Host "Make sure AdGuard Home is installed as Windows Service." -ForegroundColor Yellow
    exit 1
}

# Get config paths
$installPath = "$env:ProgramFiles\AdGuardHome"
$confDir = "$installPath\conf"
$targetConfigFile = "$confDir\AdGuardHome.yaml"
$sourceConfigFile = "$PSScriptRoot\..\config\AdGuardHome.yaml"

if (-not (Test-Path $sourceConfigFile)) {
    Write-Error "Source configuration not found: $sourceConfigFile"
    exit 1
}

if (-not (Test-Path $targetConfigFile)) {
    Write-Error "AdGuard Home configuration not found: $targetConfigFile"
    Write-Host "AdGuard Home may not be properly installed." -ForegroundColor Yellow
    exit 1
}

# Backup existing config
$backupFile = "$targetConfigFile.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "Backing up current configuration..." -ForegroundColor Yellow
Copy-Item -Path $targetConfigFile -Destination $backupFile -Force
Write-Host "  Backup saved to: $backupFile" -ForegroundColor Green

# Stop service if running
$wasRunning = $false
if ($adguardService.Status -eq "Running") {
    Write-Host "Stopping AdGuard Home service..." -ForegroundColor Yellow
    Stop-Service -Name "AdGuardHome" -Force
    Start-Sleep -Seconds 2
    $wasRunning = $true
}

# Copy new configuration
Write-Host "`nUpdating configuration with latest filters..." -ForegroundColor Yellow
Copy-Item -Path $sourceConfigFile -Destination $targetConfigFile -Force

Write-Host "`nConfiguration updated successfully!" -ForegroundColor Green
Write-Host "  - Security filters (malware, phishing, scam)" -ForegroundColor Cyan
Write-Host "  - Ads and tracking filters (world-wide)" -ForegroundColor Cyan
Write-Host "  - Adult content and gambling filters" -ForegroundColor Cyan
Write-Host "  - Custom user rules" -ForegroundColor Cyan

# Restart service
if ($RestartService -or $wasRunning) {
    Write-Host "`nStarting AdGuard Home service..." -ForegroundColor Yellow
    Start-Service -Name "AdGuardHome"
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name "AdGuardHome"
    if ($service.Status -eq "Running") {
        Write-Host "Service started successfully!" -ForegroundColor Green
    } else {
        Write-Warning "Service status: $($service.Status)"
    }
} else {
    Write-Host "`nService was not running. Start it manually:" -ForegroundColor Yellow
    Write-Host "  Start-Service AdGuardHome" -ForegroundColor White
}

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Open http://localhost:3000" -ForegroundColor White
Write-Host "2. Go to Filters > DNS blocklists" -ForegroundColor White
Write-Host "3. Verify all filters are enabled and updating" -ForegroundColor White
Write-Host "4. Check Custom filtering rules for your custom rules" -ForegroundColor White

Write-Host "`nNote: Filters will auto-update every 24 hours." -ForegroundColor Cyan
Write-Host "To force update now, go to Filters > DNS blocklists > Update" -ForegroundColor Cyan

