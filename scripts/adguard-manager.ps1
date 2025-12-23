# AdGuard Manager - Unified AdGuard Home Management
# Combines: install, configure, update, uninstall
#
# Usage:
#   .\adguard-manager.ps1                 # Interactive wizard
#   .\adguard-manager.ps1 -Install        # Install AdGuard Home
#   .\adguard-manager.ps1 -Configure      # Configure network access + rules
#   .\adguard-manager.ps1 -Update         # Update filters
#   .\adguard-manager.ps1 -Uninstall      # Remove AdGuard Home
#   .\adguard-manager.ps1 -Status         # Show status

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Update,
    [switch]$Uninstall,
    [switch]$Status,
    [switch]$Force,
    [string]$InstallPath = "$env:ProgramFiles\AdGuardHome",
    [string]$ProjectPath = (Split-Path $PSScriptRoot -Parent)
)

# Colors and formatting
function Write-Header {
    param([string]$Text)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Step {
    param([int]$Num, [int]$Total, [string]$Text)
    Write-Host "`n[$Num/$Total] $Text" -ForegroundColor Yellow
}

function Write-Success { param([string]$Text) Write-Host "[OK] $Text" -ForegroundColor Green }
function Write-Warning { param([string]$Text) Write-Host "[!] $Text" -ForegroundColor Yellow }
function Write-Info { param([string]$Text) Write-Host "[i] $Text" -ForegroundColor Gray }

# Check admin rights
function Test-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "This script requires administrator privileges!"
        exit 1
    }
}

# Get local IP
function Get-LocalIP {
    (Get-NetIPAddress -AddressFamily IPv4 | 
        Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.PrefixOrigin -ne "WellKnown" } | 
        Select-Object -First 1).IPAddress
}

# ============= STATUS =============
function Show-Status {
    Write-Header "AdGuard Home Status"
    
    $service = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
    
    if (-not $service) {
        Write-Warning "AdGuard Home is NOT installed."
        Write-Host "`nTo install, run: .\adguard-manager.ps1 -Install" -ForegroundColor Cyan
        return
    }
    
    Write-Host "Service:" -ForegroundColor Yellow
    Write-Host "  Name: AdGuardHome" -ForegroundColor White
    Write-Host "  Status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq "Running") { "Green" } else { "Red" })
    Write-Host "  Path: $InstallPath" -ForegroundColor Gray
    
    # Check ports
    Write-Host "`nPorts:" -ForegroundColor Yellow
    $dnsPort = Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue
    $webPort = Get-NetTCPConnection -LocalPort 80 -ErrorAction SilentlyContinue
    $web3000 = Get-NetTCPConnection -LocalPort 3000 -ErrorAction SilentlyContinue
    
    Write-Host "  DNS (53):  $(if ($dnsPort) { 'LISTENING' } else { 'Not listening' })" -ForegroundColor $(if ($dnsPort) { "Green" } else { "Red" })
    Write-Host "  Web (80):  $(if ($webPort) { 'LISTENING' } else { 'Not listening' })" -ForegroundColor $(if ($webPort) { "Green" } else { "Yellow" })
    Write-Host "  Web (3000): $(if ($web3000) { 'LISTENING' } else { 'Not listening' })" -ForegroundColor $(if ($web3000) { "Green" } else { "Gray" })
    
    # Check config
    $configPath = "$InstallPath\conf\AdGuardHome.yaml"
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw
        $bindHost = if ($config -match 'bind_host:\s*(\S+)') { $matches[1] } else { "unknown" }
        
        Write-Host "`nConfiguration:" -ForegroundColor Yellow
        Write-Host "  bind_host: $bindHost" -ForegroundColor White
        Write-Host "  Network access: $(if ($bindHost -eq '0.0.0.0') { 'ENABLED' } else { 'Local only' })" -ForegroundColor $(if ($bindHost -eq '0.0.0.0') { "Green" } else { "Yellow" })
    }
    
    $localIP = Get-LocalIP
    Write-Host "`nAccess URLs:" -ForegroundColor Yellow
    Write-Host "  Local: http://127.0.0.1" -ForegroundColor Cyan
    if ($localIP) {
        Write-Host "  Network: http://$localIP" -ForegroundColor Cyan
    }
    
    # DNS check
    Write-Host "`nDNS Settings:" -ForegroundColor Yellow
    $adapters = Get-DnsClientServerAddress -AddressFamily IPv4 | 
        Where-Object { $_.ServerAddresses -contains "127.0.0.1" }
    
    if ($adapters) {
        foreach ($adapter in $adapters) {
            Write-Host "  $($adapter.InterfaceAlias): Using AdGuard (127.0.0.1)" -ForegroundColor Green
        }
    } else {
        Write-Warning "  No adapters using AdGuard DNS (127.0.0.1)"
        Write-Host "  Set DNS: Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '127.0.0.1'" -ForegroundColor Gray
    }
}

# ============= INSTALL =============
function Invoke-Install {
    Test-Admin
    Write-Header "Installing AdGuard Home"
    
    $existingService = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
    if ($existingService -and -not $Force) {
        Write-Warning "AdGuard Home is already installed."
        Write-Host "Status: $($existingService.Status)" -ForegroundColor Cyan
        Write-Host "To reinstall, use: .\adguard-manager.ps1 -Install -Force" -ForegroundColor Gray
        return
    }
    
    # Ensure TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    Write-Step 1 5 "Getting latest version from GitHub..."
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" -ErrorAction Stop
        $version = $release.tag_name
        Write-Success "Latest version: $version"
    } catch {
        Write-Error "Cannot get release info: $_"
        return
    }
    
    $asset = $release.assets | Where-Object { $_.name -like "*windows_amd64*.zip" } | Select-Object -First 1
    if (-not $asset) {
        Write-Error "Windows release not found."
        return
    }
    
    Write-Step 2 5 "Downloading AdGuard Home..."
    $tempDir = "$env:TEMP\AdGuardHome_Install"
    $zipFile = "$tempDir\AdGuardHome.zip"
    
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile -UseBasicParsing
        Write-Success "Downloaded: $($asset.name)"
    } catch {
        Write-Error "Download failed: $_"
        return
    }
    
    # Remove existing if Force
    if ($existingService -and $Force) {
        Write-Info "Removing existing installation..."
        if ($existingService.Status -eq "Running") {
            Stop-Service -Name "AdGuardHome" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        $existingExe = "$InstallPath\AdGuardHome.exe"
        if (Test-Path $existingExe) {
            Start-Process -FilePath $existingExe -ArgumentList "-s", "uninstall" -Wait -NoNewWindow -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }
    
    Write-Step 3 5 "Extracting files..."
    try {
        if (-not (Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        }
        
        Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force
        $extracted = Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -like "AdGuardHome*" } | Select-Object -First 1
        
        if ($extracted) {
            Copy-Item -Path "$($extracted.FullName)\*" -Destination $InstallPath -Recurse -Force
        } else {
            Copy-Item -Path "$tempDir\AdGuardHome.exe" -Destination $InstallPath -Force -ErrorAction SilentlyContinue
        }
        Write-Success "Extracted to: $InstallPath"
    } catch {
        Write-Error "Extraction failed: $_"
        return
    }
    
    # Create directories
    $workDir = "$InstallPath\work"
    $confDir = "$InstallPath\conf"
    New-Item -ItemType Directory -Path $workDir -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path $confDir -Force -ErrorAction SilentlyContinue | Out-Null
    
    Write-Step 4 5 "Installing Windows service..."
    $adguardExe = "$InstallPath\AdGuardHome.exe"
    
    if (-not (Test-Path $adguardExe)) {
        Write-Error "AdGuardHome.exe not found!"
        return
    }
    
    try {
        $result = Start-Process -FilePath $adguardExe -ArgumentList "-s", "install" -Wait -NoNewWindow -PassThru
        Start-Sleep -Seconds 2
        Start-Service -Name "AdGuardHome"
        Start-Sleep -Seconds 3
        
        $service = Get-Service -Name "AdGuardHome"
        if ($service.Status -eq "Running") {
            Write-Success "Service started successfully!"
        } else {
            Write-Warning "Service status: $($service.Status)"
        }
    } catch {
        Write-Error "Service installation failed: $_"
        return
    }
    
    Write-Step 5 5 "Configuring firewall..."
    Get-NetFirewallRule -DisplayName "AdGuard Home*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    
    New-NetFirewallRule -DisplayName "AdGuard Home DNS (UDP)" -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow -Program $adguardExe | Out-Null
    New-NetFirewallRule -DisplayName "AdGuard Home DNS (TCP)" -Direction Inbound -Protocol TCP -LocalPort 53 -Action Allow -Program $adguardExe | Out-Null
    New-NetFirewallRule -DisplayName "AdGuard Home Web" -Direction Inbound -Protocol TCP -LocalPort 80,3000 -Action Allow -Program $adguardExe | Out-Null
    Write-Success "Firewall rules created."
    
    # Cleanup
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    
    $localIP = Get-LocalIP
    
    Write-Header "Installation Complete!"
    Write-Host "Version: $version" -ForegroundColor Green
    Write-Host "Status: Running" -ForegroundColor Green
    
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "  NEXT STEPS - Setup Wizard" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Open: http://localhost:3000" -ForegroundColor White
    Write-Host ""
    Write-Host "2. In 'Admin Web Interface':" -ForegroundColor White
    Write-Host "   Listen interface: All interfaces (0.0.0.0)" -ForegroundColor Cyan
    Write-Host "   Port: 80 (or 3000)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "3. In 'DNS server':" -ForegroundColor White
    Write-Host "   Listen interface: All interfaces (0.0.0.0)" -ForegroundColor Cyan
    Write-Host "   Port: 53" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "4. Create admin account" -ForegroundColor White
    Write-Host ""
    Write-Host "5. After wizard, run:" -ForegroundColor Yellow
    Write-Host "   .\adguard-manager.ps1 -Configure" -ForegroundColor Green
    Write-Host ""
    if ($localIP) {
        Write-Host "Network access after setup: http://$localIP" -ForegroundColor Cyan
    }
}

# ============= CONFIGURE =============
function Invoke-Configure {
    Test-Admin
    Write-Header "Configuring AdGuard Home"
    
    $configPath = "$InstallPath\conf\AdGuardHome.yaml"
    
    if (-not (Test-Path $configPath)) {
        Write-Warning "AdGuard Home configuration not found."
        Write-Host "Please complete setup wizard first at http://localhost:3000" -ForegroundColor Yellow
        return
    }
    
    Write-Step 1 3 "Backing up current configuration..."
    $backupPath = "$configPath.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $configPath -Destination $backupPath -Force
    Write-Success "Backup: $backupPath"
    
    Write-Step 2 3 "Updating configuration..."
    $content = Get-Content $configPath -Raw
    
    # Fix bind_host for network access
    $content = $content -replace 'bind_host:\s*127\.0\.0\.1', 'bind_host: 0.0.0.0'
    $content = $content -replace '(\s+bind_hosts:\s*\n\s+-\s*)127\.0\.0\.1', '$10.0.0.0'
    
    # Add user_rules if empty
    $customRules = @"
user_rules:
  - "||tiktok.com^"
  - "||tiktokcdn.com^"
  - "||discord.com^"
  - "||discordapp.com^"
  - "||facebook.com^"
  - "||instagram.com^"
  - "||twitter.com^"
  - "||x.com^"
  - "||snapchat.com^"
  - "||reddit.com^"
  - "||steampowered.com^"
  - "||steamcommunity.com^"
  - "||epicgames.com^"
  - "||fortnite.com^"
  - "||roblox.com^"
  - "||battle.net^"
"@
    
    if ($content -match 'user_rules:\s*\[\s*\]') {
        $content = $content -replace 'user_rules:\s*\[\s*\]', $customRules
        Write-Success "Added blocking rules (TikTok, Discord, Facebook, etc.)"
    } elseif ($content -notmatch 'user_rules:') {
        $content = $content + "`n" + $customRules
        Write-Success "Added blocking rules"
    } else {
        Write-Info "user_rules already exist - keeping current"
    }
    
    Set-Content -Path $configPath -Value $content -NoNewline -Encoding UTF8
    Write-Success "Configuration updated"
    
    Write-Step 3 3 "Restarting service..."
    try {
        Restart-Service -Name "AdGuardHome" -Force
        Start-Sleep -Seconds 3
        
        $service = Get-Service -Name "AdGuardHome"
        if ($service.Status -eq "Running") {
            Write-Success "Service restarted!"
        } else {
            Write-Warning "Service status: $($service.Status)"
        }
    } catch {
        Write-Error "Failed to restart: $_"
    }
    
    $localIP = Get-LocalIP
    
    Write-Header "Configuration Complete!"
    Write-Host "Network access enabled (bind_host: 0.0.0.0)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Blocked domains:" -ForegroundColor Yellow
    Write-Host "  TikTok, Discord, Facebook, Instagram, Twitter/X" -ForegroundColor White
    Write-Host "  Snapchat, Reddit, Steam, Epic Games, Fortnite, Roblox" -ForegroundColor White
    Write-Host ""
    Write-Host "Access URLs:" -ForegroundColor Yellow
    Write-Host "  Local: http://127.0.0.1" -ForegroundColor Cyan
    if ($localIP) {
        Write-Host "  Network: http://$localIP" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "Don't forget to set DNS:" -ForegroundColor Yellow
    Write-Host "  Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '127.0.0.1'" -ForegroundColor Cyan
}

# ============= UPDATE =============
function Invoke-Update {
    Test-Admin
    Write-Header "Updating AdGuard Home Filters"
    
    $configPath = "$InstallPath\conf\AdGuardHome.yaml"
    $sourceConfig = Join-Path $ProjectPath "config\AdGuardHome.yaml"
    
    if (-not (Test-Path $configPath)) {
        Write-Warning "AdGuard Home not installed."
        return
    }
    
    if (-not (Test-Path $sourceConfig)) {
        Write-Warning "Source config not found: $sourceConfig"
        return
    }
    
    Write-Step 1 2 "Backing up current configuration..."
    $backupPath = "$configPath.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $configPath -Destination $backupPath -Force
    Write-Success "Backup: $backupPath"
    
    Write-Step 2 2 "Updating filters..."
    # Keep user/password from current config
    $currentContent = Get-Content $configPath -Raw
    $newContent = Get-Content $sourceConfig -Raw
    
    # Extract users section from current
    if ($currentContent -match '(?s)(users:.*?)(?=\n\w|\z)') {
        $usersSection = $matches[1]
        $newContent = $newContent -replace '(?s)(users:.*?)(?=\n\w|\z)', $usersSection
    }
    
    Set-Content -Path $configPath -Value $newContent -NoNewline -Encoding UTF8
    
    try {
        Restart-Service -Name "AdGuardHome" -Force
        Start-Sleep -Seconds 3
        Write-Success "Filters updated and service restarted!"
    } catch {
        Write-Error "Failed to restart: $_"
    }
}

# ============= UNINSTALL =============
function Invoke-Uninstall {
    Test-Admin
    Write-Header "Uninstalling AdGuard Home"
    
    $service = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
    
    if (-not $service) {
        Write-Warning "AdGuard Home service not found."
        
        if (Test-Path $InstallPath) {
            $remove = Read-Host "Remove installation files at $InstallPath? (Y/N) [N]"
            if ($remove -eq "Y" -or $remove -eq "y") {
                Remove-Item -Path $InstallPath -Recurse -Force
                Write-Success "Files removed."
            }
        }
        return
    }
    
    Write-Step 1 4 "Stopping service..."
    if ($service.Status -eq "Running") {
        Stop-Service -Name "AdGuardHome" -Force
        Start-Sleep -Seconds 2
        Write-Success "Service stopped."
    }
    
    Write-Step 2 4 "Uninstalling service..."
    $adguardExe = "$InstallPath\AdGuardHome.exe"
    if (Test-Path $adguardExe) {
        Start-Process -FilePath $adguardExe -ArgumentList "-s", "uninstall" -Wait -NoNewWindow
        Write-Success "Service uninstalled."
    }
    
    Write-Step 3 4 "Removing firewall rules..."
    Get-NetFirewallRule -DisplayName "AdGuard Home*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Success "Firewall rules removed."
    
    Write-Step 4 4 "Removing files..."
    $keepConfig = Read-Host "Keep configuration files for future? (Y/N) [Y]"
    
    if ($keepConfig -eq "N" -or $keepConfig -eq "n") {
        Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "All files removed."
    } else {
        # Keep conf folder
        Get-ChildItem -Path $InstallPath -Exclude "conf" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Files removed (configuration kept)."
    }
    
    Write-Header "Uninstallation Complete"
    Write-Host "Don't forget to restore DNS settings:" -ForegroundColor Yellow
    Write-Host "  Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ResetServerAddresses" -ForegroundColor Cyan
}

# ============= MAIN =============
if ($Install) {
    Invoke-Install
}
elseif ($Configure) {
    Invoke-Configure
}
elseif ($Update) {
    Invoke-Update
}
elseif ($Uninstall) {
    Invoke-Uninstall
}
elseif ($Status) {
    Show-Status
}
else {
    # Interactive menu
    Write-Header "AdGuard Home Manager"
    
    Write-Host "DNS-based content filtering for parental control.`n" -ForegroundColor Gray
    Write-Host "What would you like to do?`n" -ForegroundColor White
    Write-Host "  1. Show status" -ForegroundColor Cyan
    Write-Host "  2. Install AdGuard Home" -ForegroundColor Cyan
    Write-Host "  3. Configure (network access + blocking rules)" -ForegroundColor Cyan
    Write-Host "  4. Update filters" -ForegroundColor Cyan
    Write-Host "  5. Uninstall" -ForegroundColor Red
    Write-Host "  6. Exit" -ForegroundColor Gray
    
    $choice = Read-Host "`nEnter choice (1-6)"
    
    switch ($choice) {
        "1" { Show-Status }
        "2" { Invoke-Install }
        "3" { Invoke-Configure }
        "4" { Invoke-Update }
        "5" { Invoke-Uninstall }
        "6" { exit 0 }
        default { Write-Warning "Invalid choice" }
    }
}

