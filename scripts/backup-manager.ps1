# Backup Manager - System Backup and Restore
# Combines: backup-system, restore-system
#
# Usage:
#   .\backup-manager.ps1                  # Interactive wizard
#   .\backup-manager.ps1 -Backup          # Create backup
#   .\backup-manager.ps1 -Restore         # Restore from backup
#   .\backup-manager.ps1 -List            # List available backups

param(
    [switch]$Backup,
    [switch]$Restore,
    [switch]$List,
    [string]$BackupPath,
    [switch]$SkipRestorePoint
)

$BackupRoot = "C:\ProgramData\ParentalControl\Backups"

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

# ============= LIST BACKUPS =============
function Show-Backups {
    Write-Header "Available Backups"
    
    if (-not (Test-Path $BackupRoot)) {
        Write-Warning "No backups found."
        Write-Host "Create backup: .\backup-manager.ps1 -Backup" -ForegroundColor Cyan
        return @()
    }
    
    $backups = Get-ChildItem -Path $BackupRoot -Directory | Sort-Object Name -Descending
    
    if ($backups.Count -eq 0) {
        Write-Warning "No backups found."
        return @()
    }
    
    Write-Host "Found $($backups.Count) backup(s):`n" -ForegroundColor Yellow
    
    $i = 1
    foreach ($backup in $backups) {
        $infoFile = Join-Path $backup.FullName "backup-info.txt"
        $size = (Get-ChildItem -Path $backup.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1KB
        
        Write-Host "  $i. $($backup.Name)" -ForegroundColor White
        Write-Host "     Path: $($backup.FullName)" -ForegroundColor Gray
        Write-Host "     Size: $([math]::Round($size, 2)) KB" -ForegroundColor Gray
        
        if (Test-Path $infoFile) {
            $info = Get-Content $infoFile -Head 5
            Write-Host "     Info: $($info[0])" -ForegroundColor Gray
        }
        
        Write-Host ""
        $i++
    }
    
    return $backups
}

# ============= BACKUP =============
function Invoke-Backup {
    Test-Admin
    Write-Header "Creating System Backup"
    
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $backupDir = Join-Path $BackupRoot $timestamp
    
    Write-Host "This backup includes:" -ForegroundColor Gray
    Write-Host "  - Windows Restore Point (if possible)" -ForegroundColor Gray
    Write-Host "  - Registry keys (DNS, Firewall, Policies)" -ForegroundColor Gray
    Write-Host "  - DNS settings" -ForegroundColor Gray
    Write-Host "  - Firewall rules" -ForegroundColor Gray
    Write-Host "  - Scheduled Tasks" -ForegroundColor Gray
    Write-Host ""
    
    # Create backup directory
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    
    Write-Info "Backup directory: $backupDir"
    
    $totalSteps = 5
    
    # Step 1: Restore Point
    if (-not $SkipRestorePoint) {
        Write-Step 1 $totalSteps "Creating Windows Restore Point..."
        
        $isRemote = $env:SESSIONNAME -match "^RDP-" -or $PSSenderInfo -ne $null
        
        if ($isRemote) {
            Write-Warning "Remote session detected - restore point may fail."
            Write-Info "Trying WMI method..."
        }
        
        try {
            # Enable System Protection if needed
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            
            # Try WMI method (works in remote sessions sometimes)
            $result = (Get-WmiObject -List | Where-Object { $_.Name -eq "SystemRestore" }).CreateRestorePoint(
                "Parental Control Backup - $timestamp",
                12,  # APPLICATION_INSTALL
                100  # BEGIN_NESTED_SYSTEM_CHANGE
            )
            
            if ($result.ReturnValue -eq 0) {
                Write-Success "Restore point created."
            } else {
                Write-Warning "Restore point may have failed (code: $($result.ReturnValue))"
            }
        } catch {
            Write-Warning "Could not create restore point: $_"
            Write-Info "Other backups will still be created."
        }
    } else {
        Write-Step 1 $totalSteps "Skipping Restore Point (as requested)..."
    }
    
    # Step 2: Registry
    Write-Step 2 $totalSteps "Backing up registry..."
    $regDir = Join-Path $backupDir "registry"
    New-Item -ItemType Directory -Path $regDir -Force | Out-Null
    
    $regKeys = @{
        "TCPIP" = "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        "Firewall" = "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy"
        "Policies" = "HKLM\SOFTWARE\Policies\Microsoft\Windows"
        "UserPolicies" = "HKCU\SOFTWARE\Policies\Microsoft\Windows"
    }
    
    foreach ($name in $regKeys.Keys) {
        $regFile = Join-Path $regDir "$name.reg"
        try {
            reg export $regKeys[$name] $regFile /y 2>$null | Out-Null
            Write-Success "Backed up: $name"
        } catch {
            Write-Warning "Could not backup: $name"
        }
    }
    
    # Step 3: DNS Settings
    Write-Step 3 $totalSteps "Backing up DNS settings..."
    $dnsFile = Join-Path $backupDir "dns-settings.json"
    
    try {
        $dnsSettings = Get-DnsClientServerAddress -AddressFamily IPv4 | 
            Select-Object InterfaceAlias, InterfaceIndex, ServerAddresses |
            ConvertTo-Json -Depth 3
        $dnsSettings | Set-Content $dnsFile -Encoding UTF8
        Write-Success "DNS settings backed up."
    } catch {
        Write-Warning "Could not backup DNS: $_"
    }
    
    # Step 4: Firewall Rules
    Write-Step 4 $totalSteps "Backing up Firewall rules..."
    $fwFile = Join-Path $backupDir "firewall-rules.json"
    
    try {
        Get-NetFirewallRule -DisplayName "ParentalControl-*" -ErrorAction SilentlyContinue |
            Select-Object DisplayName, Direction, Action, Enabled, Profile |
            ConvertTo-Json -Depth 3 | Set-Content $fwFile -Encoding UTF8
        Write-Success "Firewall rules backed up."
    } catch {
        Write-Warning "Could not backup firewall: $_"
    }
    
    # Step 5: Scheduled Tasks
    Write-Step 5 $totalSteps "Backing up Scheduled Tasks..."
    $taskDir = Join-Path $backupDir "tasks"
    New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
    
    try {
        $tasks = Get-ScheduledTask -TaskName "ParentalControl-*" -ErrorAction SilentlyContinue
        foreach ($task in $tasks) {
            $taskFile = Join-Path $taskDir "$($task.TaskName).xml"
            Export-ScheduledTask -TaskName $task.TaskName | Set-Content $taskFile -Encoding UTF8
            Write-Success "Backed up task: $($task.TaskName)"
        }
    } catch {
        Write-Warning "Could not backup tasks: $_"
    }
    
    # Create info file
    $infoFile = Join-Path $backupDir "backup-info.txt"
    @"
Parental Control Backup
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Computer: $env:COMPUTERNAME
User: $env:USERNAME
"@ | Set-Content $infoFile -Encoding UTF8
    
    Write-Header "Backup Complete"
    Write-Host "Location: $backupDir" -ForegroundColor Green
    Write-Host ""
    Write-Host "Contents:" -ForegroundColor Yellow
    Get-ChildItem $backupDir | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "To restore: .\backup-manager.ps1 -Restore -BackupPath `"$backupDir`"" -ForegroundColor Cyan
    
    return $backupDir
}

# ============= RESTORE =============
function Invoke-Restore {
    Test-Admin
    Write-Header "Restoring from Backup"
    
    # If no path specified, list and select
    if (-not $BackupPath) {
        $backups = Show-Backups
        if ($backups.Count -eq 0) { return }
        
        $choice = Read-Host "`nSelect backup number to restore (1-$($backups.Count))"
        
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $backups.Count) {
            $BackupPath = $backups[[int]$choice - 1].FullName
        } else {
            Write-Warning "Invalid selection."
            return
        }
    }
    
    if (-not (Test-Path $BackupPath)) {
        Write-Error "Backup not found: $BackupPath"
        return
    }
    
    Write-Host "Restoring from: $BackupPath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This will restore:" -ForegroundColor Gray
    Write-Host "  - Registry keys" -ForegroundColor Gray
    Write-Host "  - DNS settings" -ForegroundColor Gray
    Write-Host "  - Remove Parental Control components" -ForegroundColor Gray
    Write-Host ""
    
    $confirm = Read-Host "Continue? (Y/N) [N]"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Warning "Restore cancelled."
        return
    }
    
    $totalSteps = 4
    
    # Step 1: Registry
    Write-Step 1 $totalSteps "Restoring registry..."
    $regDir = Join-Path $BackupPath "registry"
    
    if (Test-Path $regDir) {
        Get-ChildItem -Path $regDir -Filter "*.reg" | ForEach-Object {
            try {
                reg import $_.FullName 2>$null
                Write-Success "Restored: $($_.BaseName)"
            } catch {
                Write-Warning "Could not restore: $($_.BaseName)"
            }
        }
    } else {
        Write-Warning "No registry backup found."
    }
    
    # Step 2: DNS
    Write-Step 2 $totalSteps "Restoring DNS settings..."
    $dnsFile = Join-Path $BackupPath "dns-settings.json"
    
    if (Test-Path $dnsFile) {
        try {
            $dnsSettings = Get-Content $dnsFile | ConvertFrom-Json
            foreach ($setting in $dnsSettings) {
                if ($setting.ServerAddresses -and $setting.ServerAddresses.Count -gt 0) {
                    Set-DnsClientServerAddress -InterfaceIndex $setting.InterfaceIndex -ServerAddresses $setting.ServerAddresses -ErrorAction SilentlyContinue
                } else {
                    Set-DnsClientServerAddress -InterfaceIndex $setting.InterfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue
                }
            }
            Write-Success "DNS settings restored."
        } catch {
            Write-Warning "Could not restore DNS: $_"
        }
    } else {
        Write-Warning "No DNS backup found."
    }
    
    # Step 3: Remove Parental Control
    Write-Step 3 $totalSteps "Removing Parental Control components..."
    
    # Stop AdGuard
    Stop-Service -Name "AdGuardHome" -Force -ErrorAction SilentlyContinue
    
    # Remove scheduled tasks
    Get-ScheduledTask -TaskName "ParentalControl-*" -ErrorAction SilentlyContinue | 
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    Write-Success "Scheduled tasks removed."
    
    # Remove firewall rules
    Get-NetFirewallRule -DisplayName "ParentalControl-*" -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    Write-Success "Firewall rules removed."
    
    # Step 4: System Restore option
    Write-Step 4 $totalSteps "System Restore..."
    
    $openRestore = Read-Host "Open Windows System Restore? (Y/N) [N]"
    if ($openRestore -eq "Y" -or $openRestore -eq "y") {
        Start-Process "rstrui.exe"
        Write-Info "System Restore wizard opened."
    }
    
    Write-Header "Restore Complete"
    Write-Host "Components restored from backup." -ForegroundColor Green
    Write-Host ""
    Write-Host "Note: AdGuard Home service was stopped but not uninstalled." -ForegroundColor Yellow
    Write-Host "To fully uninstall: .\adguard-manager.ps1 -Uninstall" -ForegroundColor Cyan
}

# ============= MAIN =============
if ($Backup) {
    Invoke-Backup
}
elseif ($Restore) {
    Invoke-Restore
}
elseif ($List) {
    Show-Backups | Out-Null
}
else {
    # Interactive menu
    Write-Header "Backup Manager"
    
    Write-Host "Backup and restore system settings before/after Parental Control.`n" -ForegroundColor Gray
    Write-Host "What would you like to do?`n" -ForegroundColor White
    Write-Host "  1. List available backups" -ForegroundColor Cyan
    Write-Host "  2. Create new backup" -ForegroundColor Cyan
    Write-Host "  3. Restore from backup" -ForegroundColor Yellow
    Write-Host "  4. Exit" -ForegroundColor Gray
    
    $choice = Read-Host "`nEnter choice (1-4)"
    
    switch ($choice) {
        "1" { Show-Backups | Out-Null }
        "2" { Invoke-Backup }
        "3" { Invoke-Restore }
        "4" { exit 0 }
        default { Write-Warning "Invalid choice" }
    }
}

