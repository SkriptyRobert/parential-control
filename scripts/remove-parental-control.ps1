# Parental Control - Complete Removal Script
# Removes all components: AdGuard Home, Firewall rules, GPO, Scheduled Tasks
#
# Usage:
#   .\remove-parental-control.ps1          # Interactive removal
#   .\remove-parental-control.ps1 -KeepLogs  # Keep log files
#
# Requires administrator privileges

param(
    [Parameter(Mandatory=$false)]
    [switch]$KeepLogs
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Remove Parental Control" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Warning: This script will completely remove all parental control components." -ForegroundColor Yellow
$response = Read-Host "Continue? (Y/N)"
if ($response -ne "Y" -and $response -ne "y") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# 1. Remove Scheduled Tasks
Write-Host "`n[1/5] Removing Scheduled Tasks..." -ForegroundColor Yellow

$parentalTasks = Get-ScheduledTask -TaskName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalTasks) {
    foreach ($task in $parentalTasks) {
        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($task.TaskName)" -ForegroundColor Green
    }
    Write-Host "Scheduled Tasks removed" -ForegroundColor Green
} else {
    Write-Host "No ParentalControl Scheduled Tasks found" -ForegroundColor Gray
}

# 2. Remove Firewall rules
Write-Host "`n[2/5] Removing Firewall rules..." -ForegroundColor Yellow

$parentalRules = Get-NetFirewallRule -DisplayName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalRules) {
    foreach ($rule in $parentalRules) {
        Remove-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($rule.DisplayName)" -ForegroundColor Green
    }
    Write-Host "Firewall rules removed ($(($parentalRules | Measure-Object).Count) rules)" -ForegroundColor Green
} else {
    Write-Host "No ParentalControl Firewall rules found" -ForegroundColor Gray
}

# 3. Stop and remove AdGuard Home
Write-Host "`n[3/5] Stopping AdGuard Home..." -ForegroundColor Yellow

$projectPath = Split-Path $PSScriptRoot -Parent

# Check for Windows Service first
$adguardService = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue

if ($adguardService) {
    Write-Host "Found AdGuard Home Windows Service." -ForegroundColor Yellow
    
    # Stop service
    if ($adguardService.Status -eq "Running") {
        Stop-Service -Name "AdGuardHome" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    
    # Uninstall service
    $adguardExe = "$env:ProgramFiles\AdGuardHome\AdGuardHome.exe"
    if (Test-Path $adguardExe) {
        Start-Process -FilePath $adguardExe -ArgumentList "-s", "uninstall" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    } else {
        sc.exe delete AdGuardHome 2>$null
    }
    
    # Remove firewall rules
    Get-NetFirewallRule -DisplayName "AdGuard Home*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    
    Write-Host "AdGuard Home service stopped and removed" -ForegroundColor Green
    
    # Optional: Remove installation files
    Write-Host "`nDo you want to remove AdGuard Home installation files? (Y/N)" -ForegroundColor Yellow
    $removeData = Read-Host
    
    if ($removeData -eq "Y" -or $removeData -eq "y") {
        $installPath = "$env:ProgramFiles\AdGuardHome"
        if (Test-Path $installPath) {
            Remove-Item -Path $installPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "AdGuard Home installation removed" -ForegroundColor Green
        }
    }
} else {
    # Check for Docker installation
    $dockerDir = Join-Path $projectPath "docker"
    $dockerComposeFile = Join-Path $dockerDir "docker-compose.yml"
    
    if (Test-Path $dockerComposeFile) {
        try {
            Push-Location $dockerDir
            
            # Stop container
            docker-compose down 2>$null
            
            Pop-Location
            Write-Host "AdGuard Home Docker container stopped and removed" -ForegroundColor Green
            
            # Optional: Remove data
            Write-Host "`nDo you want to remove AdGuard Home Docker data? (Y/N)" -ForegroundColor Yellow
            $removeData = Read-Host
            
            if ($removeData -eq "Y" -or $removeData -eq "y") {
                $dockerConfigDir = Join-Path $dockerDir "config"
                if (Test-Path $dockerConfigDir) {
                    Remove-Item -Path $dockerConfigDir -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "AdGuard Home Docker data removed" -ForegroundColor Green
                }
            }
        } catch {
            Write-Warning "Failed to stop AdGuard Home Docker: $_"
        }
    } else {
        Write-Host "No AdGuard Home installation found (neither Service nor Docker)" -ForegroundColor Gray
    }
}

# 4. Remove GPO policies (optional)
Write-Host "`n[4/5] Removing GPO policies..." -ForegroundColor Yellow

Write-Host "Do you want to remove GPO policies? (Y/N)" -ForegroundColor Yellow
$removeGPO = Read-Host

if ($removeGPO -eq "Y" -or $removeGPO -eq "y") {
    try {
        # Remove DNS settings
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "NameServer" -ErrorAction SilentlyContinue
        
        # Remove other keys
        Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_AllowAdvancedTCPIPConfig" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_AllowNetBridge_NLA" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_ShowSharedAccessUI" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableRegistryTools" -ErrorAction SilentlyContinue
        
        Write-Host "GPO policies removed" -ForegroundColor Green
    } catch {
        Write-Warning "Some GPO policies could not be removed: $_"
    }
} else {
    Write-Host "GPO policies kept" -ForegroundColor Gray
}

# 5. Remove logs and data (optional)
Write-Host "`n[5/5] Cleaning logs and data..." -ForegroundColor Yellow

$dataDir = "$env:ProgramData\ParentalControl"

if (Test-Path $dataDir) {
    if ($KeepLogs) {
        Write-Host "Logs kept in: $dataDir" -ForegroundColor Yellow
    } else {
        Write-Host "Do you want to remove logs and tracking data? (Y/N)" -ForegroundColor Yellow
        $removeLogs = Read-Host
        
        if ($removeLogs -eq "Y" -or $removeLogs -eq "y") {
            # Keep backups, remove only logs
            $logsToRemove = @(
                "$dataDir\night-shutdown.log",
                "$dataDir\daily-limit.log",
                "$dataDir\schedule-control.log",
                "$dataDir\usage-tracking.json",
                "$dataDir\schedule-last-log.txt"
            )
            
            foreach ($log in $logsToRemove) {
                if (Test-Path $log) {
                    Remove-Item -Path $log -Force -ErrorAction SilentlyContinue
                    Write-Host "  Removed: $log" -ForegroundColor Green
                }
            }
            
            Write-Host "Logs removed (backups kept)" -ForegroundColor Green
        } else {
            Write-Host "Logs kept" -ForegroundColor Gray
        }
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Removal Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Removed components:" -ForegroundColor Yellow
Write-Host "  [OK] Scheduled Tasks" -ForegroundColor Green
Write-Host "  [OK] Firewall rules" -ForegroundColor Green
Write-Host "  [OK] AdGuard Home" -ForegroundColor Green

if ($removeGPO -eq "Y" -or $removeGPO -eq "y") {
    Write-Host "  [OK] GPO policies" -ForegroundColor Green
}

Write-Host "`nRecommended next steps:" -ForegroundColor Yellow
Write-Host "1. Restart computer" -ForegroundColor White
Write-Host "2. Check DNS settings and set to automatic" -ForegroundColor White
Write-Host "3. Verify applications work normally" -ForegroundColor White

Write-Host "`nNote: Backups are kept in: $env:ProgramData\ParentalControl\Backups" -ForegroundColor Cyan
Write-Host "To restore system from restore point run: rstrui.exe" -ForegroundColor Cyan
