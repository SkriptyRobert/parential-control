# Main Installation Script - Install all parental control components
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
    [ValidateSet("Auto", "Docker", "Service")]
    [string]$AdGuardMode = "Auto"
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

# Function to check if Docker is available and working
function Test-DockerAvailable {
    try {
        $docker = Get-Command docker -ErrorAction SilentlyContinue
        if (-not $docker) {
            return $false
        }
        
        $result = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
        
        # Check if docker daemon is running
        if ($result -match "Cannot connect" -or $result -match "error" -or $result -match "failed to connect") {
            return $false
        }
        
        return $true
    } catch {
        return $false
    }
}

# 1. AdGuard Home
if (-not $SkipAdGuard) {
    Write-Host "`n[1/4] Installing AdGuard Home..." -ForegroundColor Yellow
    
    $useDocker = $false
    $useService = $false
    
    if ($AdGuardMode -eq "Auto") {
        # Auto-detect: check if Docker is available
        Write-Host "Detecting installation method..." -ForegroundColor Yellow
        
        $dockerAvailable = Test-DockerAvailable
        
        if ($dockerAvailable) {
            Write-Host "Docker is available and running." -ForegroundColor Green
            Write-Host "`nChoose AdGuard Home installation method:" -ForegroundColor Yellow
            Write-Host "  1) Docker container (requires Docker Desktop running)" -ForegroundColor White
            Write-Host "  2) Windows Service (native, no Docker needed) [Recommended for Win10]" -ForegroundColor White
            $choice = Read-Host "Enter choice (1 or 2)"
            
            if ($choice -eq "1") {
                $useDocker = $true
            } else {
                $useService = $true
            }
        } else {
            Write-Host "Docker is not available or not running." -ForegroundColor Yellow
            Write-Host "Installing AdGuard Home as Windows Service (native)..." -ForegroundColor Cyan
            $useService = $true
        }
    } elseif ($AdGuardMode -eq "Docker") {
        $useDocker = $true
    } elseif ($AdGuardMode -eq "Service") {
        $useService = $true
    }
    
    if ($useDocker) {
        Write-Host "Installing via Docker..." -ForegroundColor Yellow
        $adguardScript = Join-Path $ScriptsPath "install-adguard.ps1"
        if (Test-Path $adguardScript) {
            & $adguardScript -ProjectPath $ProjectPath
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Docker installation failed. Trying Windows Service..."
                $useService = $true
                $useDocker = $false
            }
        } else {
            Write-Warning "Docker script not found, using Windows Service..."
            $useService = $true
        }
    }
    
    if ($useService) {
        Write-Host "Installing as Windows Service..." -ForegroundColor Yellow
        $serviceScript = Join-Path $ScriptsPath "install-adguard-service.ps1"
        if (Test-Path $serviceScript) {
            $configDir = Join-Path $ProjectPath "adguard-config"
            & $serviceScript -ConfigPath $configDir
            # Note: $LASTEXITCODE is set by the child script
        } else {
            Write-Warning "AdGuard Home service script not found: $serviceScript"
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

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. If you installed AdGuard Home, complete setup at http://localhost:3000" -ForegroundColor White
Write-Host "2. Set DNS on this PC to 127.0.0.1" -ForegroundColor White
Write-Host "3. Edit time limits in config\time-limits.json as needed" -ForegroundColor White
Write-Host "4. Edit app blocklist in config\apps-to-block.json" -ForegroundColor White
Write-Host "5. For Android phones use guide in android-setup.md" -ForegroundColor White

Write-Host "`nTo check Scheduled Tasks run:" -ForegroundColor Cyan
Write-Host "  Get-ScheduledTask -TaskName 'ParentalControl-*'" -ForegroundColor White

Write-Host "`nTo check Firewall rules run:" -ForegroundColor Cyan
Write-Host "  Get-NetFirewallRule -DisplayName 'ParentalControl-*'" -ForegroundColor White

# Show AdGuard Home status
$adguardService = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
if ($adguardService) {
    Write-Host "`nAdGuard Home (Windows Service):" -ForegroundColor Cyan
    Write-Host "  Status: $($adguardService.Status)" -ForegroundColor White
    Write-Host "  Manage: Get-Service AdGuardHome | Start-Service / Stop-Service" -ForegroundColor White
} else {
    $dockerContainer = docker ps --filter "name=adguard" --format "{{.Names}}" 2>$null
    if ($dockerContainer) {
        Write-Host "`nAdGuard Home (Docker):" -ForegroundColor Cyan
        Write-Host "  Container: $dockerContainer" -ForegroundColor White
        Write-Host "  Manage: docker-compose up/down" -ForegroundColor White
    }
}
