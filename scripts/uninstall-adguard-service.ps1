# Uninstall AdGuard Home Windows Service
# Requires administrator privileges

param(
    [Parameter(Mandatory=$false)]
    [string]$InstallPath = "$env:ProgramFiles\AdGuardHome",
    
    [Parameter(Mandatory=$false)]
    [switch]$KeepConfig
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n=== Uninstalling AdGuard Home Windows Service ===" -ForegroundColor Cyan

# Check if service exists
$service = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue

if (-not $service) {
    Write-Host "AdGuard Home service is not installed." -ForegroundColor Yellow
    
    # Check if files exist
    if (Test-Path $InstallPath) {
        Write-Host "Installation directory found: $InstallPath" -ForegroundColor Yellow
        $removeFiles = Read-Host "Remove installation files? (Y/N)"
        if ($removeFiles -eq "Y" -or $removeFiles -eq "y") {
            Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Installation files removed." -ForegroundColor Green
        }
    }
    exit 0
}

# Stop service if running
if ($service.Status -eq "Running") {
    Write-Host "Stopping service..." -ForegroundColor Yellow
    Stop-Service -Name "AdGuardHome" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Uninstall service
$adguardExe = "$InstallPath\AdGuardHome.exe"

if (Test-Path $adguardExe) {
    Write-Host "Uninstalling service..." -ForegroundColor Yellow
    try {
        Start-Process -FilePath $adguardExe -ArgumentList "-s", "uninstall" -Wait -NoNewWindow
        Start-Sleep -Seconds 2
        Write-Host "Service uninstalled." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to uninstall service via AdGuardHome.exe: $_"
        
        # Try sc.exe as fallback
        Write-Host "Trying alternative method..." -ForegroundColor Yellow
        sc.exe delete AdGuardHome 2>$null
    }
} else {
    Write-Host "AdGuardHome.exe not found, trying sc.exe..." -ForegroundColor Yellow
    sc.exe delete AdGuardHome 2>$null
}

# Verify service removed
Start-Sleep -Seconds 2
$serviceCheck = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
if ($serviceCheck) {
    Write-Warning "Service may still exist. Restart may be required."
} else {
    Write-Host "Service successfully removed." -ForegroundColor Green
}

# Remove firewall rules
Write-Host "Removing firewall rules..." -ForegroundColor Yellow
Get-NetFirewallRule -DisplayName "AdGuard Home*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
Write-Host "Firewall rules removed." -ForegroundColor Green

# Remove installation files
if (-not $KeepConfig) {
    if (Test-Path $InstallPath) {
        $removeFiles = Read-Host "Remove installation files and configuration? (Y/N)"
        if ($removeFiles -eq "Y" -or $removeFiles -eq "y") {
            Write-Host "Removing installation files..." -ForegroundColor Yellow
            Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Installation files removed." -ForegroundColor Green
        } else {
            Write-Host "Installation files kept in: $InstallPath" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Configuration kept (-KeepConfig)." -ForegroundColor Yellow
}

Write-Host "`n=== Uninstallation Complete ===" -ForegroundColor Green

