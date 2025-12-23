# Configure AdGuard Home for Network Access
# Run this AFTER completing setup wizard via web interface
#
# This script:
# 1. Changes bind_host from 127.0.0.1 to 0.0.0.0 (all interfaces)
# 2. Adds custom blocking rules (user_rules)
# 3. Restarts the service
#
# Usage:
#   .\configure-adguard-network.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = (Split-Path $PSScriptRoot -Parent)
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n=== Configuring AdGuard Home for Network Access ===" -ForegroundColor Cyan

$adguardPath = "$env:ProgramFiles\AdGuardHome"
$configPath = "$adguardPath\conf\AdGuardHome.yaml"
$sourceConfigPath = Join-Path $ProjectPath "config\AdGuardHome.yaml"

# Check if AdGuard Home is installed
if (-not (Test-Path $configPath)) {
    Write-Error "AdGuard Home configuration not found at: $configPath"
    Write-Host "Please run install-all.ps1 first and complete setup wizard." -ForegroundColor Yellow
    exit 1
}

# Backup current config
$backupPath = "$configPath.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Write-Host "Backing up current config to: $backupPath" -ForegroundColor Yellow
Copy-Item -Path $configPath -Destination $backupPath -Force

# Read current config
$content = Get-Content $configPath -Raw

# Fix bind_host (change 127.0.0.1 to 0.0.0.0)
Write-Host "Configuring web interface for all network interfaces (0.0.0.0)..." -ForegroundColor Yellow

# Replace bind_host: 127.0.0.1 with bind_host: 0.0.0.0
$content = $content -replace 'bind_host:\s*127\.0\.0\.1', 'bind_host: 0.0.0.0'

# Also fix in dns section if present
$content = $content -replace '(\s+bind_hosts:\s*\n\s+-\s*)127\.0\.0\.1', '$10.0.0.0'

# Check if user_rules section exists and is empty or minimal
Write-Host "Adding custom blocking rules..." -ForegroundColor Yellow

# Define user rules to add
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

# Check if user_rules exists
if ($content -match 'user_rules:\s*\[\s*\]') {
    # Empty user_rules - replace with our rules
    $content = $content -replace 'user_rules:\s*\[\s*\]', $customRules
    Write-Host "  Added blocking rules (was empty)" -ForegroundColor Green
} elseif ($content -notmatch 'user_rules:') {
    # No user_rules section - add it
    $content = $content + "`n" + $customRules
    Write-Host "  Added blocking rules (new section)" -ForegroundColor Green
} else {
    Write-Host "  user_rules already exist - keeping current rules" -ForegroundColor Yellow
    Write-Host "  To update rules, edit config manually or use web interface" -ForegroundColor Cyan
}

# Save config
Set-Content -Path $configPath -Value $content -NoNewline -Encoding UTF8
Write-Host "Configuration saved." -ForegroundColor Green

# Restart service
Write-Host "Restarting AdGuard Home service..." -ForegroundColor Yellow
try {
    Restart-Service -Name "AdGuardHome" -Force -ErrorAction Stop
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name "AdGuardHome"
    if ($service.Status -eq "Running") {
        Write-Host "Service restarted successfully!" -ForegroundColor Green
    } else {
        Write-Warning "Service status: $($service.Status)"
    }
} catch {
    Write-Error "Failed to restart service: $_"
    exit 1
}

# Get local IP
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1).IPAddress

Write-Host "`n=== Configuration Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Web interface is now accessible from:" -ForegroundColor Green
Write-Host "  Local:   http://127.0.0.1 (or :3000 if using that port)" -ForegroundColor White
if ($localIP) {
    Write-Host "  Network: http://$localIP (or :3000)" -ForegroundColor White
}
Write-Host ""
Write-Host "Blocked domains:" -ForegroundColor Yellow
Write-Host "  TikTok, Discord, Facebook, Instagram, Twitter/X" -ForegroundColor White
Write-Host "  Snapchat, Reddit, Steam, Epic Games, Fortnite, Roblox, Battle.net" -ForegroundColor White
Write-Host ""
Write-Host "To add more blocked domains:" -ForegroundColor Cyan
Write-Host "  1. Open web interface -> Filters -> Custom filtering rules" -ForegroundColor White
Write-Host "  2. Add rule: ||domain.com^" -ForegroundColor White
Write-Host ""

exit 0

