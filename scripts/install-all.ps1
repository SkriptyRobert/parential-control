# Parental Control - Main Installation Script
# Installs all components: AdGuard Home, Firewall rules, GPO, Scheduled Tasks
#
# Usage:
#   .\install-all.ps1                    # Interactive installation
#   .\install-all.ps1 -AdGuardMode Service  # Force Windows Service
#   .\install-all.ps1 -SkipGPO           # Skip GPO policies
#
# Requires administrator privileges

param(
    [Parameter(Mandatory=$false)]
    [switch]$SkipAdGuard,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipFirewall,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipGPO,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipScheduledTasks,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBackup,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Service", "Docker")]
    [string]$AdGuardMode = "Service"
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    Write-Host "Run PowerShell as administrator and run this script again." -ForegroundColor Yellow
    exit 1
}

$ScriptsPath = $PSScriptRoot
$ProjectPath = Split-Path $ScriptsPath -Parent

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Parental Control Installation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Backup recommendation
if (-not $SkipBackup) {
    Write-Host "Recommendation: Create system backup before installation!" -ForegroundColor Yellow
    Write-Host "Run: .\scripts\backup-system.ps1`n" -ForegroundColor Cyan

    $createBackup = Read-Host "Create backup now? (Y/N)"
    if ($createBackup -eq "Y" -or $createBackup -eq "y") {
        $backupScript = Join-Path $ScriptsPath "backup-system.ps1"
        if (Test-Path $backupScript) {
            & $backupScript
            Write-Host "`nBackup complete. Continuing with installation...`n" -ForegroundColor Green
            Start-Sleep -Seconds 2
        }
    }
}

# Create directories
$dataDir = "$env:ProgramData\ParentalControl"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    Write-Host "Created data directory: $dataDir" -ForegroundColor Green
}

# 1. AdGuard Home
if (-not $SkipAdGuard) {
    Write-Host "`n[1/4] Installing AdGuard Home..." -ForegroundColor Yellow
    
    if ($AdGuardMode -eq "Service") {
        Write-Host "Installing as Windows Service (recommended)..." -ForegroundColor Yellow
        $serviceScript = Join-Path $ScriptsPath "install-adguard-service.ps1"
        if (Test-Path $serviceScript) {
            $configDir = Join-Path $ProjectPath "config"
            & $serviceScript -ConfigPath $configDir
        } else {
            Write-Warning "AdGuard Home service script not found: $serviceScript"
        }
    } elseif ($AdGuardMode -eq "Docker") {
        Write-Host "Installing via Docker..." -ForegroundColor Yellow
        $dockerDir = Join-Path $ProjectPath "docker"
        $adguardScript = Join-Path $dockerDir "install-docker-adguard.ps1"
        if (Test-Path $adguardScript) {
            & $adguardScript -ProjectPath $dockerDir
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Docker installation failed!"
            }
        } else {
            Write-Warning "Docker installation script not found: $adguardScript"
            Write-Host "For Docker installation, use scripts in the 'docker' folder." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`n[1/4] Skipped: AdGuard Home" -ForegroundColor Gray
}

# 2. Windows Firewall Rules
if (-not $SkipFirewall) {
    Write-Host "`n[2/4] Setting up Windows Firewall rules..." -ForegroundColor Yellow
    $firewallScript = Join-Path $ScriptsPath "firewall-rules.ps1"
    if (Test-Path $firewallScript) {
        & $firewallScript
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Firewall rules created successfully." -ForegroundColor Green
        } else {
            Write-Warning "Some firewall rules could not be created."
        }
    } else {
        Write-Warning "Firewall script not found: $firewallScript"
    }
} else {
    Write-Host "`n[2/4] Skipped: Windows Firewall" -ForegroundColor Gray
}

# 3. GPO Policies
if (-not $SkipGPO) {
    Write-Host "`n[3/4] Applying GPO policies..." -ForegroundColor Yellow
    Write-Host "Warning: GPO policies will be applied. Continue? (Y/N)" -ForegroundColor Yellow
    $response = Read-Host
    if ($response -eq "Y" -or $response -eq "y") {
        $gpoScript = Join-Path $ScriptsPath "apply-gpo-policies.ps1"
        if (Test-Path $gpoScript) {
            & $gpoScript
        } else {
            Write-Warning "GPO script not found: $gpoScript"
        }
    } else {
        Write-Host "GPO policies skipped. You can apply them later manually." -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[3/4] Skipped: GPO Policies" -ForegroundColor Gray
}

# 4. Scheduled Tasks
if (-not $SkipScheduledTasks) {
    Write-Host "`n[4/4] Setting up Scheduled Tasks..." -ForegroundColor Yellow
    $tasksScript = Join-Path $ScriptsPath "setup-scheduled-tasks.ps1"
    if (Test-Path $tasksScript) {
        & $tasksScript -ScriptsPath $ScriptsPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Scheduled Tasks set up successfully." -ForegroundColor Green
        } else {
            Write-Warning "Some Scheduled Tasks could not be created."
        }
    } else {
        Write-Warning "Scheduled Tasks script not found: $tasksScript"
    }
} else {
    Write-Host "`n[4/4] Skipped: Scheduled Tasks" -ForegroundColor Gray
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Installation Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Complete AdGuard Home setup at http://localhost:3000" -ForegroundColor White
Write-Host "   - Use 0.0.0.0 for Web Interface (not 127.0.0.1!)" -ForegroundColor Cyan
Write-Host "   - Use 0.0.0.0 for DNS Server" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. After setup wizard, run:" -ForegroundColor White
Write-Host "   .\scripts\adguard-manager.ps1 -Configure" -ForegroundColor Green
Write-Host "   (This enables network access and adds blocking rules)" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Set DNS to 127.0.0.1:" -ForegroundColor White
Write-Host "   Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '127.0.0.1'" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. Configure time limits:" -ForegroundColor White
Write-Host "   .\scripts\time-control.ps1 -Configure" -ForegroundColor Cyan
Write-Host ""
Write-Host "5. Configure app-specific limits:" -ForegroundColor White
Write-Host "   .\scripts\app-limits.ps1 -Configure" -ForegroundColor Cyan
Write-Host ""

Write-Host "MANAGEMENT TOOLS:" -ForegroundColor Yellow
Write-Host "  .\scripts\time-control.ps1      - Time limits management" -ForegroundColor White
Write-Host "  .\scripts\app-limits.ps1        - Per-app time limits" -ForegroundColor White
Write-Host "  .\scripts\adguard-manager.ps1   - DNS filtering" -ForegroundColor White
Write-Host "  .\scripts\backup-manager.ps1    - Backup/restore" -ForegroundColor White
Write-Host ""
Write-Host "GUI (requires Python):" -ForegroundColor Yellow
Write-Host "  gui\start-gui.bat" -ForegroundColor Cyan
Write-Host ""

# Show AdGuard Home status
$adguardService = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
if ($adguardService) {
    Write-Host "AdGuard Home Status: $($adguardService.Status)" -ForegroundColor $(if ($adguardService.Status -eq "Running") { "Green" } else { "Yellow" })
}

