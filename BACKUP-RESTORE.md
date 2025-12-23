# Backup and Restore Guide

How to backup system before installation and restore if needed.

## Why Backup?

Parental Control modifies:
- Windows Registry
- DNS settings
- Firewall rules
- Scheduled Tasks
- Group Policy (optional)

Creating a backup ensures you can restore the system to its original state.

## Creating Backup

### Quick Backup

```powershell
.\scripts\backup-system.ps1
```

### What Gets Backed Up

| Item | Location |
|------|----------|
| Windows Restore Point | System |
| Registry Keys | `Backups\<timestamp>\Registry\` |
| DNS Settings | `Backups\<timestamp>\dns-settings.json` |
| Firewall Rules | `Backups\<timestamp>\firewall-rules.csv` |
| Scheduled Tasks | `Backups\<timestamp>\scheduled-tasks.csv` |

### Backup Location

```
C:\ProgramData\ParentalControl\Backups\2025-12-23_14-30-00\
├── Registry\
│   ├── TCP-IP-Parameters.reg
│   ├── FirewallPolicy.reg
│   ├── Windows-Policies.reg
│   └── ...
├── dns-settings.json
├── firewall-rules.csv
├── scheduled-tasks.csv
├── backup-info.json
└── restore-point-info.json
```

### Verify Backup

```powershell
# List backups
Get-ChildItem "$env:ProgramData\ParentalControl\Backups"

# Check specific backup
Get-ChildItem "$env:ProgramData\ParentalControl\Backups\2025-12-23_14-30-00"
```

## Restoring from Backup

### Quick Restore

```powershell
.\scripts\restore-system.ps1 -BackupPath "C:\ProgramData\ParentalControl\Backups\2025-12-23_14-30-00"
```

### What Gets Restored

1. Registry keys (DNS, Policies)
2. DNS settings on network adapters
3. Option to use Windows System Restore

### Manual Registry Restore

```powershell
# Import specific registry file
reg import "C:\ProgramData\ParentalControl\Backups\...\Registry\TCP-IP-Parameters.reg"
```

### Windows System Restore

If you created a restore point during backup:

```powershell
# Open System Restore wizard
rstrui.exe
```

Or:
1. Open Control Panel
2. System and Security > System
3. System Protection > System Restore
4. Choose the "Parental Control" restore point

## Remote Session Backup

### Known Limitations

- Creating restore points may fail via remote session
- Use `-SkipRestorePoint` parameter if needed

### Remote Backup

```powershell
# Connect to remote PC
Enter-PSSession -ComputerName "CHILD-PC" -Credential (Get-Credential)

# Run backup (skip restore point if issues)
.\scripts\backup-system.ps1 -SkipRestorePoint
```

### Alternative: Create Restore Point Locally

1. Log into child's PC directly (RDP or physically)
2. Run backup without `-SkipRestorePoint`
3. Continue with remote installation

## Backup Commands Reference

```powershell
# Create backup
.\scripts\backup-system.ps1

# Create backup, skip restore point
.\scripts\backup-system.ps1 -SkipRestorePoint

# Restore from backup
.\scripts\restore-system.ps1 -BackupPath "<path>"

# List all backups
Get-ChildItem "$env:ProgramData\ParentalControl\Backups" | Sort-Object LastWriteTime -Descending

# Check restore points
Get-ComputerRestorePoint
```

## Troubleshooting

### Restore Point Failed

```
Warning: Failed to create restore point
```

Causes:
- Remote session limitation
- System Protection disabled
- Recent restore point exists (24h limit)

Solution:
- Use `-SkipRestorePoint` for remote sessions
- Enable System Protection in System Properties
- Registry and other backups still work

### Registry Import Failed

```powershell
# Check if file exists
Test-Path "C:\ProgramData\ParentalControl\Backups\...\Registry\TCP-IP-Parameters.reg"

# Import with elevated privileges
Start-Process regedit -ArgumentList "/s `"$regFile`"" -Verb RunAs
```

### DNS Not Restored

```powershell
# Manually reset DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses

# Or set specific DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "8.8.8.8","8.8.4.4"
```

## Best Practices

1. **Always backup before installation** - First step every time
2. **Verify backup completed** - Check backup folder exists and has files
3. **Note the backup path** - You'll need it for restore
4. **Keep backups** - Don't delete until sure everything works
5. **Test restore** - On non-critical system first if possible
