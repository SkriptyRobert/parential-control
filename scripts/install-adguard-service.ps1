# Install AdGuard Home as Windows Service
# Parental Control - Primary Installation Method
#
# Downloads latest AdGuard Home from GitHub and installs as Windows service.
# No Docker required - runs natively on Windows.
#
# Usage:
#   .\install-adguard-service.ps1
#   .\install-adguard-service.ps1 -Force  # Reinstall

param(
    [Parameter(Mandatory=$false)]
    [string]$InstallPath = "$env:ProgramFiles\AdGuardHome",
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n=== Installing AdGuard Home as Windows Service ===" -ForegroundColor Cyan

# Check if already installed
$existingService = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
if ($existingService -and -not $Force) {
    Write-Host "AdGuard Home service is already installed." -ForegroundColor Yellow
    Write-Host "Status: $($existingService.Status)" -ForegroundColor Cyan
    Write-Host "To reinstall, use -Force parameter." -ForegroundColor Yellow
    exit 0
}

# Ensure TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Get latest release from GitHub
$apiUrl = "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest"
Write-Host "Getting latest release info from GitHub..." -ForegroundColor Yellow

try {
    $release = Invoke-RestMethod -Method Get -Uri $apiUrl -ErrorAction Stop
    $version = $release.tag_name
    Write-Host "Latest version: $version" -ForegroundColor Green
} catch {
    Write-Error "Cannot get release info from GitHub: $_"
    exit 1
}

# Find Windows AMD64 asset
$asset = $release.assets | Where-Object { $_.name -like "*windows_amd64*" -and $_.name -like "*.zip" } | Select-Object -First 1

if (-not $asset) {
    Write-Error "Windows AMD64 release not found."
    exit 1
}

# Download
$tempDir = "$env:TEMP\AdGuardHome_Install"
$zipFile = "$tempDir\AdGuardHome.zip"

if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

Write-Host "Downloading: $($asset.name)..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile -UseBasicParsing
} catch {
    Write-Error "Failed to download: $_"
    exit 1
}

# Stop and uninstall existing service if Force
if ($existingService -and $Force) {
    Write-Host "Stopping and removing existing service..." -ForegroundColor Yellow
    
    if ($existingService.Status -eq "Running") {
        Stop-Service -Name "AdGuardHome" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    
    # Uninstall service
    $existingExe = "$InstallPath\AdGuardHome.exe"
    if (Test-Path $existingExe) {
        Start-Process -FilePath $existingExe -ArgumentList "-s", "uninstall" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

# Extract
Write-Host "Extracting to: $InstallPath..." -ForegroundColor Yellow

# Create install directory
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
}

# Extract ZIP
try {
    Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force
    
    # Find extracted folder (usually AdGuardHome)
    $extractedDir = Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -like "AdGuardHome*" } | Select-Object -First 1
    
    if ($extractedDir) {
        # Copy contents to install path
        Copy-Item -Path "$($extractedDir.FullName)\*" -Destination $InstallPath -Recurse -Force
    } else {
        # Maybe files are directly in temp
        Copy-Item -Path "$tempDir\AdGuardHome.exe" -Destination $InstallPath -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Error "Failed to extract: $_"
    exit 1
}

# Verify executable exists
$adguardExe = "$InstallPath\AdGuardHome.exe"
if (-not (Test-Path $adguardExe)) {
    Write-Error "AdGuardHome.exe not found after extraction!"
    exit 1
}

# Create work and conf directories
$workDir = "$InstallPath\work"
$confDir = "$InstallPath\conf"

if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
}
if (-not (Test-Path $confDir)) {
    New-Item -ItemType Directory -Path $confDir -Force | Out-Null
}

# Copy pre-configured AdGuardHome.yaml
$preConfigFile = "$ConfigPath\AdGuardHome.yaml"
$targetConfigFile = "$confDir\AdGuardHome.yaml"

if (Test-Path $preConfigFile) {
    if (Test-Path $targetConfigFile) {
        # Backup existing config before overwriting
        $backupFile = "$targetConfigFile.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -Path $targetConfigFile -Destination $backupFile -Force
        Write-Host "Backed up existing config to: $backupFile" -ForegroundColor Yellow
    }
    
    Write-Host "Copying pre-configured AdGuardHome.yaml with all filters..." -ForegroundColor Yellow
    Copy-Item -Path $preConfigFile -Destination $targetConfigFile -Force
    Write-Host "Pre-configured settings and filters applied." -ForegroundColor Green
    Write-Host "  - Security filters (malware, phishing, scam)" -ForegroundColor Cyan
    Write-Host "  - Ads and tracking filters (world-wide)" -ForegroundColor Cyan
    Write-Host "  - Adult content and gambling filters" -ForegroundColor Cyan
    Write-Host "  - Custom user rules" -ForegroundColor Cyan
} else {
    Write-Warning "Pre-configured AdGuardHome.yaml not found at: $preConfigFile"
    Write-Host "AdGuard Home will use default configuration. You can add filters manually via web interface." -ForegroundColor Yellow
}

# Install as Windows service
Write-Host "Installing as Windows service..." -ForegroundColor Yellow

try {
    $result = Start-Process -FilePath $adguardExe -ArgumentList "-s", "install" -Wait -NoNewWindow -PassThru
    
    if ($result.ExitCode -ne 0) {
        Write-Warning "Service installation returned code: $($result.ExitCode)"
    }
} catch {
    Write-Error "Failed to install service: $_"
    exit 1
}

# Verify service installed
Start-Sleep -Seconds 2
$service = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue

if (-not $service) {
    Write-Error "Service not found after installation!"
    exit 1
}

# Start service
Write-Host "Starting service..." -ForegroundColor Yellow

try {
    Start-Service -Name "AdGuardHome"
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name "AdGuardHome"
    if ($service.Status -eq "Running") {
        Write-Host "Service started successfully!" -ForegroundColor Green
    } else {
        Write-Warning "Service status: $($service.Status)"
    }
} catch {
    Write-Error "Failed to start service: $_"
}

# Configure Windows Firewall
Write-Host "Configuring Windows Firewall..." -ForegroundColor Yellow

# Remove old rules
Get-NetFirewallRule -DisplayName "AdGuard Home*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

# Add new rules
try {
    New-NetFirewallRule -DisplayName "AdGuard Home DNS (UDP)" -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow -Program $adguardExe | Out-Null
    New-NetFirewallRule -DisplayName "AdGuard Home DNS (TCP)" -Direction Inbound -Protocol TCP -LocalPort 53 -Action Allow -Program $adguardExe | Out-Null
    New-NetFirewallRule -DisplayName "AdGuard Home Web" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow -Program $adguardExe | Out-Null
    Write-Host "Firewall rules created." -ForegroundColor Green
} catch {
    Write-Warning "Failed to create firewall rules: $_"
}

# Cleanup
Write-Host "Cleaning up..." -ForegroundColor Yellow
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  AdGuard Home Installation Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Installation path: $InstallPath" -ForegroundColor Green
Write-Host "Version: $version" -ForegroundColor Green
Write-Host "Service status: $((Get-Service -Name 'AdGuardHome').Status)" -ForegroundColor Green

# Get local IP for network access info
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1).IPAddress

Write-Host "`nWeb interface: http://localhost:3000" -ForegroundColor Cyan
Write-Host "DNS server: 127.0.0.1:53" -ForegroundColor Cyan

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  IMPORTANT: Setup Wizard Instructions" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Open: http://localhost:3000" -ForegroundColor White
Write-Host ""
Write-Host "2. In 'Admin Web Interface' step:" -ForegroundColor White
Write-Host "   Listen interface: All interfaces (0.0.0.0)" -ForegroundColor Cyan
Write-Host "   Port: 80 (or 3000)" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. In 'DNS server' step:" -ForegroundColor White
Write-Host "   Listen interface: All interfaces (0.0.0.0)" -ForegroundColor Cyan
Write-Host "   Port: 53" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. Create admin username and password" -ForegroundColor White
Write-Host ""
Write-Host "5. After wizard, run this to add blocking rules:" -ForegroundColor Yellow
Write-Host "   .\scripts\configure-adguard-network.ps1" -ForegroundColor Green
Write-Host ""
if ($localIP) {
    Write-Host "Network access after setup: http://$localIP" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "Service commands:" -ForegroundColor Cyan
Write-Host "  Start:   Start-Service AdGuardHome" -ForegroundColor White
Write-Host "  Stop:    Stop-Service AdGuardHome" -ForegroundColor White
Write-Host "  Restart: Restart-Service AdGuardHome" -ForegroundColor White
Write-Host "  Status:  Get-Service AdGuardHome" -ForegroundColor White

# Success
exit 0
