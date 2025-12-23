# System Backup - Parental Control
# Requires administrator privileges
# Supports remote session (RDP, PSRemoting)

param(
    [Parameter(Mandatory=$false)]
    [string]$BackupPath = "$env:ProgramData\ParentalControl\Backups",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipRestorePoint
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  System Backup - Parental Control" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupDir = Join-Path $BackupPath $timestamp

# Create backup directory
if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
}

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Write-Host "Backup directory: $backupDir" -ForegroundColor Green

# 1. Create restore point (System Restore Point)
Write-Host "`n[1/5] Creating restore point..." -ForegroundColor Yellow

# Detect remote session
$isRemoteSession = $false
if ($env:SESSIONNAME -match "RDP-Tcp" -or $PSSenderInfo -or $host.Name -match "ServerRemoteHost") {
    $isRemoteSession = $true
    Write-Host "Remote session detected (RDP/PSRemoting)" -ForegroundColor Yellow
}

if ($SkipRestorePoint) {
    Write-Host "Skipped restore point creation (-SkipRestorePoint parameter)" -ForegroundColor Yellow
} elseif ($isRemoteSession) {
    Write-Host "Warning: Creating restore point via remote session may fail" -ForegroundColor Yellow
    Write-Host "Note: If it fails, registry and settings backup will still be created" -ForegroundColor Yellow
}

if (-not $SkipRestorePoint) {
    try {
        # Enable System Protection if not enabled
        $systemDrive = $env:SystemDrive
        
        # Check if System Protection is enabled
        $systemProtection = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        
        if (-not $systemProtection) {
            Write-Host "System Protection is not enabled. Trying to enable..." -ForegroundColor Yellow
            Enable-ComputerRestore -Drive "$systemDrive\" -ErrorAction SilentlyContinue
        }
        
        # Create restore point
        $restorePointDescription = "Parental Control - Before installation - $timestamp"
        
        if ($isRemoteSession) {
            # For remote session use WMI method
            Write-Host "Trying to create restore point via WMI..." -ForegroundColor Yellow
            try {
                $sr = Get-WmiObject -List -Namespace root\default | Where-Object {$_.Name -eq "SystemRestore"}
                if ($sr) {
                    $result = $sr.CreateRestorePoint($restorePointDescription, 0, 100)
                    if ($result.ReturnValue -eq 0) {
                        Write-Host "Restore point created via WMI: $restorePointDescription" -ForegroundColor Green
                    } else {
                        throw "WMI restore point creation failed (code: $($result.ReturnValue))"
                    }
                } else {
                    throw "SystemRestore WMI class not found"
                }
            } catch {
                Write-Warning "WMI method failed: $_"
                Write-Host "Trying standard method..." -ForegroundColor Yellow
                Checkpoint-Computer -Description $restorePointDescription -RestorePointType "MODIFY_SETTINGS"
                Write-Host "Restore point created: $restorePointDescription" -ForegroundColor Green
            }
        } else {
            # Local session - standard method
            Checkpoint-Computer -Description $restorePointDescription -RestorePointType "MODIFY_SETTINGS"
            Write-Host "Restore point created: $restorePointDescription" -ForegroundColor Green
        }
        
        # Save restore point info
        $restoreInfo = @{
            Description = $restorePointDescription
            Timestamp = $timestamp
            Date = (Get-Date).ToString("o")
            RemoteSession = $isRemoteSession
        }
        $restoreInfo | ConvertTo-Json | Set-Content "$backupDir\restore-point-info.json" -Encoding UTF8
        
    } catch {
        Write-Warning "Failed to create restore point: $_"
        Write-Host "Continuing with registry and firewall backup..." -ForegroundColor Yellow
        Write-Host "Tip: Use -SkipRestorePoint parameter to skip restore point" -ForegroundColor Cyan
    }
} else {
    # Save info that restore point was skipped
    $restoreInfo = @{
        Description = "Skipped (remote session or -SkipRestorePoint)"
        Timestamp = $timestamp
        Date = (Get-Date).ToString("o")
        RemoteSession = $isRemoteSession
        Skipped = $true
    }
    $restoreInfo | ConvertTo-Json | Set-Content "$backupDir\restore-point-info.json" -Encoding UTF8
}

# 2. Backup registry (important keys)
Write-Host "`n[2/5] Backing up registry..." -ForegroundColor Yellow

$registryBackupDir = Join-Path $backupDir "Registry"
New-Item -ItemType Directory -Path $registryBackupDir -Force | Out-Null

# Important keys to backup
$registryKeys = @(
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; Name = "TCP-IP-Parameters"},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy"; Name = "FirewallPolicy"},
    @{Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows"; Name = "Windows-Policies"},
    @{Path = "HKCU:\Software\Policies\Microsoft\Windows"; Name = "User-Windows-Policies"},
    @{Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies"; Name = "User-Policies"}
)

foreach ($key in $registryKeys) {
    $regFile = Join-Path $registryBackupDir "$($key.Name).reg"
    
    # Convert HKLM: to HKEY_LOCAL_MACHINE for reg.exe
    $regPath = $key.Path -replace "HKLM:", "HKEY_LOCAL_MACHINE" -replace "HKCU:", "HKEY_CURRENT_USER"
    
    try {
        # Export registry key
        $result = Start-Process -FilePath "reg.exe" -ArgumentList "export", "`"$regPath`"", "`"$regFile`"", "/y" -Wait -NoNewWindow -PassThru
        
        if ($result.ExitCode -eq 0) {
            Write-Host "  Backed up: $($key.Name)" -ForegroundColor Green
        } else {
            Write-Warning "  Failed to backup: $($key.Name) (key may not exist)"
        }
    } catch {
        Write-Warning "  Error backing up $($key.Name): $_"
    }
}

# 3. Backup current DNS settings
Write-Host "`n[3/5] Backing up DNS settings..." -ForegroundColor Yellow

$dnsSettings = Get-DnsClientServerAddress | Where-Object {$_.ServerAddresses.Count -gt 0} | Select-Object InterfaceAlias, InterfaceIndex, ServerAddresses
$dnsSettings | ConvertTo-Json -Depth 10 | Set-Content "$backupDir\dns-settings.json" -Encoding UTF8
Write-Host "DNS settings backed up" -ForegroundColor Green

# 4. Backup current Firewall rules
Write-Host "`n[4/5] Backing up Firewall rules..." -ForegroundColor Yellow

# Export all firewall rules
$firewallRules = Get-NetFirewallRule | Select-Object DisplayName, Description, Direction, Action, Enabled, Profile
$firewallRules | Export-Csv -Path "$backupDir\firewall-rules.csv" -NoTypeInformation -Encoding UTF8

# Export ParentalControl specific rules (if they exist)
$parentalRules = Get-NetFirewallRule -DisplayName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalRules) {
    $parentalRules | Export-Csv -Path "$backupDir\parental-firewall-rules.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "  Backed up $(($parentalRules | Measure-Object).Count) ParentalControl firewall rules" -ForegroundColor Yellow
}

Write-Host "Firewall rules backed up" -ForegroundColor Green

# 5. Backup current Scheduled Tasks
Write-Host "`n[5/5] Backing up Scheduled Tasks..." -ForegroundColor Yellow

$scheduledTasks = Get-ScheduledTask | Select-Object TaskName, TaskPath, State, Author
$scheduledTasks | Export-Csv -Path "$backupDir\scheduled-tasks.csv" -NoTypeInformation -Encoding UTF8

# Export ParentalControl specific tasks (if they exist)
$parentalTasks = Get-ScheduledTask -TaskName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalTasks) {
    foreach ($task in $parentalTasks) {
        $taskXml = Export-ScheduledTask -TaskName $task.TaskName
        $taskXml | Set-Content "$backupDir\task-$($task.TaskName).xml" -Encoding UTF8
    }
    Write-Host "  Backed up $(($parentalTasks | Measure-Object).Count) ParentalControl scheduled tasks" -ForegroundColor Yellow
}

Write-Host "Scheduled Tasks backed up" -ForegroundColor Green

# Create info file
Write-Host "`nCreating info file..." -ForegroundColor Yellow

$windowsVersion = "Unknown"
try {
    $windowsVersion = (Get-ComputerInfo -ErrorAction SilentlyContinue).WindowsVersion
} catch {
    try {
        $windowsVersion = (Get-WmiObject Win32_OperatingSystem).Version
    } catch {
        $windowsVersion = [System.Environment]::OSVersion.Version.ToString()
    }
}

$backupInfo = @{
    Timestamp = $timestamp
    Date = (Get-Date).ToString("o")
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    WindowsVersion = $windowsVersion
    BackupPath = $backupDir
    Components = @{
        RestorePoint = (-not $SkipRestorePoint)
        Registry = $true
        DNS = $true
        Firewall = $true
        ScheduledTasks = $true
    }
}

$backupInfo | ConvertTo-Json -Depth 10 | Set-Content "$backupDir\backup-info.json" -Encoding UTF8

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Backup Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Backup location: $backupDir" -ForegroundColor Green
Write-Host "`nBacked up components:" -ForegroundColor Yellow

# Check if restore point was created
$restorePointCreated = $false
if (Test-Path "$backupDir\restore-point-info.json") {
    $rpInfo = Get-Content "$backupDir\restore-point-info.json" | ConvertFrom-Json
    if (-not $rpInfo.Skipped) {
        $restorePointCreated = $true
    }
}

if ($restorePointCreated) {
    Write-Host "  [OK] Windows Restore Point" -ForegroundColor Green
} elseif ($SkipRestorePoint) {
    Write-Host "  [--] Windows Restore Point (skipped)" -ForegroundColor Yellow
} elseif ($isRemoteSession) {
    Write-Host "  [??] Windows Restore Point (may have failed in remote session)" -ForegroundColor Yellow
} else {
    Write-Host "  [XX] Windows Restore Point (failed)" -ForegroundColor Red
}

Write-Host "  [OK] Registry keys" -ForegroundColor Green
Write-Host "  [OK] DNS settings" -ForegroundColor Green
Write-Host "  [OK] Firewall rules" -ForegroundColor Green
Write-Host "  [OK] Scheduled Tasks" -ForegroundColor Green

if ($isRemoteSession) {
    Write-Host "`nNote: Backup was created via remote session." -ForegroundColor Cyan
    Write-Host "Registry, DNS, Firewall and Scheduled Tasks are fully backed up." -ForegroundColor Cyan
}

Write-Host "`nTo restore from backup run:" -ForegroundColor Cyan
Write-Host "  .\scripts\restore-system.ps1 -BackupPath `"$backupDir`"" -ForegroundColor White

# Save last backup directory
$backupDir | Set-Content "$BackupPath\last-backup.txt" -Encoding UTF8

Write-Host "`nYou can now safely proceed with parental control installation." -ForegroundColor Green
