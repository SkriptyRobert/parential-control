# Parental Control for Windows

Complete parental control solution for Windows PCs. DNS filtering, application blocking, time limits, and scheduled access control.

## Features

- **DNS Filtering** - Block adult content, gambling, social media, and tracking via AdGuard Home
- **Application Blocking** - Block specific applications via Windows Firewall
- **Time Limits** - Daily usage limits with automatic shutdown
- **Night Mode** - Automatic shutdown between midnight and 6 AM
- **Schedule Control** - Define allowed time windows per day
- **Local Solution** - Everything runs locally, no cloud dependency

## Quick Start

```powershell
# 1. Download or clone this repository to child's PC

# 2. Run PowerShell as Administrator

# 3. Create backup (recommended)
.\scripts\backup-system.ps1

# 4. Install all components
.\scripts\install-all.ps1

# 5. Complete AdGuard Home setup at http://localhost:3000

# 6. Set DNS to 127.0.0.1
```

## Project Structure

```
Parental-Control/
├── config/                    # Configuration files
│   ├── AdGuardHome.yaml       # DNS filter configuration
│   ├── apps-to-block.json     # Applications to block
│   └── time-limits.json       # Time restrictions
├── filters/                   # Custom DNS blocklists
│   ├── adult-content.txt      # Adult/porn sites
│   ├── social-media.txt       # Social networks
│   ├── gaming.txt             # Gaming platforms
│   ├── gambling.txt           # Gambling sites
│   ├── ads-tracking.txt       # Ads and tracking
│   └── custom-rules.txt       # Your custom rules
├── scripts/                   # PowerShell scripts
│   ├── install-all.ps1        # Main installer
│   ├── remove-parental-control.ps1
│   ├── backup-system.ps1
│   └── ...
├── docker/                    # Docker alternative (optional)
│   ├── docker-compose.yml
│   └── install-docker-adguard.ps1
└── gpo/                       # Group Policy settings
    └── registry-export.reg
```

## Installation

### Prerequisites

- Windows 10/11
- Administrator access
- PowerShell 5.1+

### Step-by-Step Installation

#### 1. Prepare the System

```powershell
# Open PowerShell as Administrator
# Navigate to project folder
cd C:\path\to\Parental-Control

# Create system backup
.\scripts\backup-system.ps1
```

#### 2. Run Installation

```powershell
.\scripts\install-all.ps1
```

The installer will:
1. Install AdGuard Home as Windows Service
2. Configure Windows Firewall rules
3. Set up scheduled tasks for time limits

#### 3. Configure AdGuard Home

1. Open http://localhost:3000 in browser
2. Create admin account
3. Complete setup wizard

**Note:** All filters are automatically configured during installation:
- Security filters (malware, phishing, scam)
- Ads and tracking filters (world-wide)
- Adult content and gambling filters
- Custom user rules

Filters are pre-configured and will auto-update every 24 hours.

#### 4. Set DNS

```powershell
# Set DNS to use AdGuard Home
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "127.0.0.1"

# Verify
Get-DnsClientServerAddress -InterfaceAlias "Ethernet"
```

## Configuration

### Time Limits (config/time-limits.json)

```json
{
  "excludedUsers": ["rdpuser", "Administrator"],
  "dailyLimit": {
    "enabled": true,
    "hours": 2,
    "warningAtMinutes": 15,
    "action": "shutdown"
  },
  "nightShutdown": {
    "enabled": true,
    "startTime": "00:00",
    "endTime": "06:00"
  },
  "schedule": {
    "enabled": true,
    "allowedWindows": [
      {"day": "Monday", "start": "15:00", "end": "20:00"},
      {"day": "Saturday", "start": "09:00", "end": "21:00"}
    ]
  }
}
```

### Application Blocking (config/apps-to-block.json)

```json
{
  "applications": [
    {
      "name": "Steam",
      "paths": ["C:\\Program Files (x86)\\Steam\\steam.exe"],
      "processNames": ["steam.exe"]
    }
  ]
}
```

### DNS Filters

Edit files in `filters/` folder to customize blocking:
- `adult-content.txt` - Pornographic sites
- `social-media.txt` - TikTok, Discord, Facebook, etc.
- `gaming.txt` - Steam, Epic Games, Roblox, etc.
- `gambling.txt` - Betting and casino sites
- `custom-rules.txt` - Your own rules

After editing, add lists in AdGuard Home web interface:
1. Go to Filters > DNS blocklists
2. Add custom list > Enter local path or paste content

## Management

### Check Status

```powershell
.\scripts\check-status.ps1
```

### Update Filters

To update AdGuard Home with latest filters from configuration:

```powershell
.\scripts\update-adguard-filters.ps1
```

This will:
- Backup current configuration
- Update with latest filters (security, ads, tracking, etc.)
- Restart service if it was running

### Service Commands

```powershell
# AdGuard Home
Get-Service AdGuardHome
Start-Service AdGuardHome
Stop-Service AdGuardHome
Restart-Service AdGuardHome

# Scheduled Tasks
Get-ScheduledTask -TaskName "ParentalControl-*"

# Firewall Rules
Get-NetFirewallRule -DisplayName "ParentalControl-*"
```

### Uninstall

```powershell
.\scripts\remove-parental-control.ps1
```

## Remote Management

For remote installation via PSRemoting, see [REMOTE-SESSION.md](REMOTE-SESSION.md).

```powershell
# Connect to remote PC
$session = New-PSSession -ComputerName "CHILD-PC" -Credential (Get-Credential)

# Copy scripts
Copy-Item -Path ".\*" -Destination "C:\ParentalControl" -ToSession $session -Recurse

# Run installation
Invoke-Command -Session $session -ScriptBlock {
    Set-Location "C:\ParentalControl"
    .\scripts\install-all.ps1
}
```

## Docker Alternative

For Docker-based installation (requires Docker Desktop):

```powershell
cd docker
.\install-docker-adguard.ps1
```

See [docker/README.md](docker/README.md) for details.

## Troubleshooting

### AdGuard Home not blocking

1. Verify DNS is set to 127.0.0.1
2. Clear DNS cache: `ipconfig /flushdns`
3. Check AdGuard Home is running: `Get-Service AdGuardHome`
4. Verify filters are enabled in web interface

### Scheduled Tasks not running

```powershell
# Check task status
Get-ScheduledTask -TaskName "ParentalControl-*" | Get-ScheduledTaskInfo

# Run task manually
Start-ScheduledTask -TaskName "ParentalControl-NightShutdown"
```

### Reset DNS to automatic

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses
```

## Backup and Restore

### Create Backup

```powershell
.\scripts\backup-system.ps1
```

Creates backup of:
- Windows Restore Point
- Registry keys
- DNS settings
- Firewall rules

### Restore from Backup

```powershell
.\scripts\restore-system.ps1 -BackupPath "C:\ProgramData\ParentalControl\Backups\2025-12-23_..."
```

## Security Notes

- Scripts modify system settings and require Administrator privileges
- Excluded users (rdpuser, Administrator) are not affected by time limits
- GPO policies should only be applied to child accounts, not admin accounts
- Keep admin credentials secure and separate from children

## Files Reference

| Script | Description |
|--------|-------------|
| `install-all.ps1` | Main installer |
| `remove-parental-control.ps1` | Complete uninstaller |
| `backup-system.ps1` | System backup |
| `restore-system.ps1` | Restore from backup |
| `check-status.ps1` | Status check |
| `install-adguard-service.ps1` | AdGuard Home service installer |
| `firewall-rules.ps1` | Firewall rules management |
| `night-shutdown.ps1` | Night shutdown logic |
| `daily-limit.ps1` | Daily usage tracking |
| `schedule-control.ps1` | Schedule enforcement |
| `setup-scheduled-tasks.ps1` | Task scheduler setup |

## License

MIT License - Free for personal use.

## Support

For issues and questions, check the documentation files:
- [QUICK-START.md](QUICK-START.md) - Quick setup guide
- [REMOTE-SESSION.md](REMOTE-SESSION.md) - Remote installation
- [BACKUP-RESTORE.md](BACKUP-RESTORE.md) - Backup procedures
- [HOW-TO-ADD-RULES.md](HOW-TO-ADD-RULES.md) - Adding custom rules
