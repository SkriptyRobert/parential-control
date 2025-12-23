# Quick Start Guide

Get Parental Control running in 5 minutes.

## Prerequisites

- Windows 10/11 PC
- Administrator account
- PowerShell (built into Windows)

## Installation Steps

### 1. Download Project

Download this repository to the child's PC:
- Via Git: `git clone <repository-url>`
- Or download ZIP and extract

### 2. Open PowerShell as Administrator

1. Press `Win + X`
2. Select "Windows PowerShell (Admin)" or "Terminal (Admin)"
3. Navigate to project folder:

```powershell
cd C:\path\to\Parental-Control
```

### 3. Create Backup (Recommended)

```powershell
.\scripts\backup-system.ps1
```

This creates a restore point and backs up current settings.

### 4. Run Installation

```powershell
.\scripts\install-all.ps1
```

Follow the prompts. The script will install:
- AdGuard Home (DNS filtering)
- Windows Firewall rules (app blocking)
- Scheduled Tasks (time limits)

### 5. Setup AdGuard Home

1. Open browser: http://localhost:3000
2. Create admin username and password
3. Click through setup wizard
4. Note: Filters are pre-configured

### 6. Configure DNS

Set the PC to use AdGuard Home for DNS:

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "127.0.0.1"
```

Or manually:
1. Open Settings > Network & Internet
2. Click your connection > Properties
3. Edit DNS server assignment
4. Set to Manual, IPv4: 127.0.0.1

### 7. Verify Installation

```powershell
.\scripts\check-status.ps1
```

Test blocking by trying to access a blocked site.

## What Gets Installed

| Component | Purpose |
|-----------|---------|
| AdGuard Home | DNS filtering (blocks websites) |
| Firewall Rules | Blocks applications (Steam, Discord, etc.) |
| Night Shutdown | Shuts down PC after midnight |
| Daily Limit | Tracks usage, shuts down after 2 hours |
| Schedule Control | Only allows PC use during set hours |

## Default Settings

- **Daily limit**: 2 hours per day
- **Night shutdown**: 00:00 - 06:00
- **Allowed hours**: 15:00-20:00 weekdays, 09:00-21:00 weekends
- **Excluded users**: rdpuser, Administrator (not affected by limits)

## Customization

### Edit Time Limits

Open `config\time-limits.json`:

```json
{
  "dailyLimit": {
    "hours": 3  // Change to 3 hours
  }
}
```

### Add Blocked Applications

Open `config\apps-to-block.json` and add new entries.

Then run:
```powershell
.\scripts\firewall-rules.ps1
```

### Add Blocked Websites

Option 1: Edit `filters\custom-rules.txt`:
```
||blocked-site.com^
```

Option 2: Use AdGuard Home web interface:
- Go to Filters > Custom filtering rules
- Add rules in same format

## Common Commands

```powershell
# Check status
.\scripts\check-status.ps1

# Check AdGuard Home service
Get-Service AdGuardHome

# View scheduled tasks
Get-ScheduledTask -TaskName "ParentalControl-*"

# View firewall rules
Get-NetFirewallRule -DisplayName "ParentalControl-*"
```

## Uninstallation

```powershell
.\scripts\remove-parental-control.ps1
```

This removes all components and restores original settings.

## Troubleshooting

### Website not blocked

```powershell
# Clear DNS cache
ipconfig /flushdns

# Verify DNS setting
Get-DnsClientServerAddress

# Check AdGuard Home is running
Get-Service AdGuardHome
```

### Time limits not working

```powershell
# Check if tasks exist
Get-ScheduledTask -TaskName "ParentalControl-*"

# Check last run result
Get-ScheduledTask -TaskName "ParentalControl-DailyLimit" | Get-ScheduledTaskInfo
```

### Need to bypass temporarily

As administrator, disable the scheduled task:
```powershell
Disable-ScheduledTask -TaskName "ParentalControl-DailyLimit"

# Re-enable later
Enable-ScheduledTask -TaskName "ParentalControl-DailyLimit"
```

## Next Steps

- Read [README.md](README.md) for full documentation
- See [HOW-TO-ADD-RULES.md](HOW-TO-ADD-RULES.md) for adding custom blocks
- Check [REMOTE-SESSION.md](REMOTE-SESSION.md) for remote management
