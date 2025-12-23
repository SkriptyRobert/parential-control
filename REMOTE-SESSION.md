# Remote Session Guide

How to install and manage Parental Control remotely via PowerShell.

## Prerequisites

### On Admin PC
- PowerShell 5.1+
- Network access to child's PC

### On Child's PC
- PowerShell Remoting enabled
- WinRM service running
- Firewall allows WinRM (TCP 5985/5986)

## Enable PowerShell Remoting

### On Child's PC (One-time Setup)

Run as Administrator:

```powershell
# Enable remoting
Enable-PSRemoting -Force

# Allow connections from your admin PC
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "ADMIN-PC-NAME" -Force

# Or allow from any PC (less secure)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# Restart WinRM
Restart-Service WinRM
```

### On Admin PC

```powershell
# Allow connections to child PC
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "CHILD-PC-NAME" -Force
```

## Connect to Remote PC

### Interactive Session

```powershell
# Create session
$session = New-PSSession -ComputerName "192.168.0.180" -Credential (Get-Credential)

# Enter session
Enter-PSSession $session

# Now you're on the remote PC
# Exit with: exit
```

### Using IP Address

```powershell
$cred = Get-Credential
$session = New-PSSession -ComputerName "192.168.0.180" -Credential $cred
```

## Installation via Remote Session

### Step 1: Copy Project Files

```powershell
# Create session
$cred = Get-Credential -UserName "CHILD-PC\Administrator"
$session = New-PSSession -ComputerName "192.168.0.180" -Credential $cred

# Create destination folder
Invoke-Command -Session $session -ScriptBlock {
    New-Item -ItemType Directory -Path "C:\ParentalControl" -Force
}

# Copy all files
Copy-Item -Path "C:\Path\To\Parental-Control\*" -Destination "C:\ParentalControl" -ToSession $session -Recurse -Force
```

### Step 2: Run Backup

```powershell
Invoke-Command -Session $session -ScriptBlock {
    Set-Location "C:\ParentalControl"
    .\scripts\backup-system.ps1 -SkipRestorePoint
}
```

Note: Use `-SkipRestorePoint` because restore points often fail via remote session.

### Step 3: Run Installation

```powershell
Invoke-Command -Session $session -ScriptBlock {
    Set-Location "C:\ParentalControl"
    .\scripts\install-all.ps1 -SkipGPO
}
```

Note: Skip GPO to avoid applying policies to admin account.

### Step 4: Verify Installation

```powershell
Invoke-Command -Session $session -ScriptBlock {
    # Check AdGuard Home service
    Get-Service AdGuardHome
    
    # Check scheduled tasks
    Get-ScheduledTask -TaskName "ParentalControl-*"
    
    # Check firewall rules
    Get-NetFirewallRule -DisplayName "ParentalControl-*" | Measure-Object
}
```

## Remote Management Commands

### Check Status

```powershell
Invoke-Command -Session $session -ScriptBlock {
    C:\ParentalControl\scripts\check-status.ps1
}
```

### Restart AdGuard Home

```powershell
Invoke-Command -Session $session -ScriptBlock {
    Restart-Service AdGuardHome
}
```

### View Logs

```powershell
Invoke-Command -Session $session -ScriptBlock {
    Get-Content "$env:ProgramData\ParentalControl\night-shutdown.log" -Tail 20
}
```

### Modify Configuration

```powershell
# Copy updated config
Copy-Item -Path ".\config\time-limits.json" -Destination "C:\ParentalControl\config\" -ToSession $session -Force
```

### Run Removal

```powershell
Invoke-Command -Session $session -ScriptBlock {
    Set-Location "C:\ParentalControl"
    .\scripts\remove-parental-control.ps1
}
```

## Access AdGuard Home Web Interface

### Option 1: SSH Tunnel (if available)

```powershell
ssh -L 3000:localhost:3000 user@192.168.0.180
# Then open http://localhost:3000
```

### Option 2: Direct Access

If firewall allows, access directly:
```
http://192.168.0.180:3000
```

Firewall rule is created during installation.

### Option 3: Temporary Port Forward

```powershell
# On child PC, allow remote access temporarily
Invoke-Command -Session $session -ScriptBlock {
    New-NetFirewallRule -DisplayName "AdGuard-Temp" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
}

# Access http://192.168.0.180:3000

# Remove when done
Invoke-Command -Session $session -ScriptBlock {
    Remove-NetFirewallRule -DisplayName "AdGuard-Temp"
}
```

## Troubleshooting

### Connection Failed

```
WinRM cannot complete the operation
```

Solutions:
1. Verify WinRM is running: `Get-Service WinRM`
2. Check firewall: `Get-NetFirewallRule -DisplayName "*WinRM*"`
3. Verify TrustedHosts: `Get-Item WSMan:\localhost\Client\TrustedHosts`

### Access Denied

```
Access is denied
```

Solutions:
1. Use correct credentials (local admin on child PC)
2. Format: `COMPUTERNAME\Username` or `Username@domain`
3. Verify account has admin rights

### Scripts Not Running

```
Scripts are disabled on this system
```

Solution:
```powershell
Invoke-Command -Session $session -ScriptBlock {
    Set-ExecutionPolicy RemoteSigned -Force
}
```

### Restore Point Fails

This is expected behavior for remote sessions. Use `-SkipRestorePoint`:

```powershell
.\scripts\backup-system.ps1 -SkipRestorePoint
```

Registry and other backups will still work.

## Security Considerations

1. **Use specific TrustedHosts** - Don't use "*" in production
2. **Use strong credentials** - Different from child's account
3. **Close sessions** - `Remove-PSSession $session` when done
4. **Consider HTTPS** - Configure WinRM for HTTPS in production
5. **Audit access** - Enable PowerShell logging on child PC

## Quick Reference

```powershell
# Connect
$session = New-PSSession -ComputerName "IP" -Credential (Get-Credential)

# Run command
Invoke-Command -Session $session -ScriptBlock { command }

# Copy to remote
Copy-Item -Path "file" -Destination "path" -ToSession $session

# Interactive session
Enter-PSSession $session

# Close session
Remove-PSSession $session
```
