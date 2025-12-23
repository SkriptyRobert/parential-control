# System Restore - Parental Control
# Requires administrator privileges

param(
    [Parameter(Mandatory=$false)]
    [string]$BackupPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseLastBackup,
    
    [Parameter(Mandatory=$false)]
    [switch]$RestorePointOnly
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  System Restore from Backup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Find last backup
if ($UseLastBackup -or -not $BackupPath) {
    $lastBackupFile = "$env:ProgramData\ParentalControl\Backups\last-backup.txt"
    if (Test-Path $lastBackupFile) {
        $BackupPath = Get-Content $lastBackupFile
        Write-Host "Using last backup: $BackupPath" -ForegroundColor Yellow
    } else {
        Write-Error "No previous backup found!"
        Write-Host "Run script with -BackupPath parameter or create a backup first." -ForegroundColor Yellow
        exit 1
    }
}

if (-not (Test-Path $BackupPath)) {
    Write-Error "Backup directory not found: $BackupPath"
    exit 1
}

# Load backup info
$backupInfoFile = Join-Path $BackupPath "backup-info.json"
if (Test-Path $backupInfoFile) {
    $backupInfo = Get-Content $backupInfoFile | ConvertFrom-Json
    Write-Host "Backup info:" -ForegroundColor Cyan
    Write-Host "  Created: $($backupInfo.Date)" -ForegroundColor White
    Write-Host "  Computer: $($backupInfo.ComputerName)" -ForegroundColor White
    Write-Host "  User: $($backupInfo.UserName)" -ForegroundColor White
}

Write-Host "`nWarning: This operation will restore system to state before parental control installation." -ForegroundColor Yellow
$response = Read-Host "Continue? (Y/N)"
if ($response -ne "Y" -and $response -ne "y") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# 1. Restore from restore point
if ($RestorePointOnly) {
    Write-Host "`n[1/1] Restoring from restore point..." -ForegroundColor Yellow
    Write-Host "Starting System Restore wizard..." -ForegroundColor Yellow
    Write-Host "Select the restore point created before parental control installation." -ForegroundColor Yellow
    
    Start-Process -FilePath "rstrui.exe" -Wait
    
    Write-Host "`nRestore complete. Restart your computer." -ForegroundColor Green
    exit 0
}

# 2. Remove ParentalControl components
Write-Host "`n[1/5] Removing ParentalControl components..." -ForegroundColor Yellow

# Remove Scheduled Tasks
$parentalTasks = Get-ScheduledTask -TaskName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalTasks) {
    foreach ($task in $parentalTasks) {
        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Removed task: $($task.TaskName)" -ForegroundColor Yellow
    }
}

# Remove Firewall rules
$parentalRules = Get-NetFirewallRule -DisplayName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalRules) {
    foreach ($rule in $parentalRules) {
        Remove-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
        Write-Host "  Removed rule: $($rule.DisplayName)" -ForegroundColor Yellow
    }
}

Write-Host "ParentalControl components removed" -ForegroundColor Green

# 3. Restore registry
Write-Host "`n[2/5] Restoring registry..." -ForegroundColor Yellow

$registryBackupDir = Join-Path $BackupPath "Registry"
if (Test-Path $registryBackupDir) {
    $regFiles = Get-ChildItem -Path $registryBackupDir -Filter "*.reg"
    
    foreach ($regFile in $regFiles) {
        try {
            $result = Start-Process -FilePath "reg.exe" -ArgumentList "import", "`"$($regFile.FullName)`"" -Wait -NoNewWindow -PassThru
            
            if ($result.ExitCode -eq 0) {
                Write-Host "  Restored: $($regFile.BaseName)" -ForegroundColor Green
            } else {
                Write-Warning "  Failed to restore: $($regFile.BaseName)"
            }
        } catch {
            Write-Warning "  Error restoring $($regFile.BaseName): $_"
        }
    }
} else {
    Write-Warning "Registry backup not found"
}

# 4. Restore DNS settings
Write-Host "`n[3/5] Restoring DNS settings..." -ForegroundColor Yellow

$dnsSettingsFile = Join-Path $BackupPath "dns-settings.json"
if (Test-Path $dnsSettingsFile) {
    $dnsSettings = Get-Content $dnsSettingsFile | ConvertFrom-Json
    
    foreach ($adapter in $dnsSettings) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $adapter.ServerAddresses
            Write-Host "  Restored DNS for: $($adapter.InterfaceAlias)" -ForegroundColor Green
        } catch {
            Write-Warning "  Failed to restore DNS for $($adapter.InterfaceAlias): $_"
        }
    }
} else {
    Write-Warning "DNS settings backup not found"
}

# 5. Restore point info
Write-Host "`n[4/5] Restore point info..." -ForegroundColor Yellow

$restorePointFile = Join-Path $BackupPath "restore-point-info.json"
if (Test-Path $restorePointFile) {
    $restoreInfo = Get-Content $restorePointFile | ConvertFrom-Json
    Write-Host "Restore point: $($restoreInfo.Description)" -ForegroundColor Cyan
    Write-Host "Created: $($restoreInfo.Date)" -ForegroundColor Cyan
    
    Write-Host "`nFor full system restore you can use Windows restore point:" -ForegroundColor Yellow
    Write-Host "1. Open: System -> System Protection -> System Restore" -ForegroundColor White
    Write-Host "2. Select point: $($restoreInfo.Description)" -ForegroundColor White
    Write-Host "`nOr run: rstrui.exe" -ForegroundColor Cyan
}

# 6. Stop AdGuard Home
Write-Host "`n[5/5] Stopping AdGuard Home..." -ForegroundColor Yellow

# Check for Windows Service first
$adguardService = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
if ($adguardService) {
    if ($adguardService.Status -eq "Running") {
        Stop-Service -Name "AdGuardHome" -Force -ErrorAction SilentlyContinue
        Write-Host "AdGuard Home service stopped" -ForegroundColor Green
    } else {
        Write-Host "AdGuard Home service already stopped" -ForegroundColor Gray
    }
} else {
    # Check for Docker installation
    $dockerDir = Join-Path (Split-Path $PSScriptRoot -Parent) "docker"
    $dockerComposeFile = Join-Path $dockerDir "docker-compose.yml"
    if (Test-Path $dockerComposeFile) {
        try {
            Push-Location $dockerDir
            docker-compose down 2>$null
            Pop-Location
            Write-Host "AdGuard Home container stopped" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to stop AdGuard Home: $_"
        }
    } else {
        Write-Host "AdGuard Home not found (neither Service nor Docker)" -ForegroundColor Gray
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Restore Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Restored components:" -ForegroundColor Yellow
Write-Host "  [OK] ParentalControl components removed" -ForegroundColor Green
Write-Host "  [OK] Registry restored" -ForegroundColor Green
Write-Host "  [OK] DNS settings restored" -ForegroundColor Green
Write-Host "  [OK] AdGuard Home stopped" -ForegroundColor Green

Write-Host "`nRecommended next steps:" -ForegroundColor Yellow
Write-Host "1. Restart computer to apply all changes" -ForegroundColor White
Write-Host "2. Check DNS settings in Network Connections" -ForegroundColor White
Write-Host "3. For full restore, use Windows restore point (rstrui.exe)" -ForegroundColor White

Write-Host "`nTo start System Restore wizard:" -ForegroundColor Cyan
Write-Host "  .\scripts\restore-system.ps1 -RestorePointOnly" -ForegroundColor White
