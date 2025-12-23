# How to Add Blocking Rules

Guide for adding custom website and application blocking rules.

## Blocking Websites (DNS)

### Method 1: Custom Filters File

1. Open `filters\custom-rules.txt`
2. Add rules using AdBlock syntax:

```
# Block domain and all subdomains
||example.com^

# Block specific subdomain
||games.example.com^

# Block domains containing keyword
||*keyword*^

# Whitelist (allow) a domain
@@||allowed-site.com^
```

3. Add the file to AdGuard Home:
   - Open http://localhost:3000
   - Go to Filters > DNS blocklists
   - Click "Add blocklist"
   - Choose "Add a custom list"
   - Enter file path or paste content

### Method 2: AdGuard Home Web Interface

1. Open http://localhost:3000
2. Go to Filters > Custom filtering rules
3. Add rules directly:

```
||tiktok.com^
||discord.com^
```

4. Click "Apply"

### Method 3: Blocked Services (Easiest)

1. Open http://localhost:3000
2. Go to Filters > Blocked services
3. Toggle services to block (Discord, TikTok, Steam, etc.)
4. Changes apply immediately

## DNS Rule Syntax

| Pattern | Description | Example |
|---------|-------------|---------|
| `\|\|domain.com^` | Block domain and subdomains | `\|\|facebook.com^` |
| `@@\|\|domain.com^` | Allow (whitelist) domain | `@@\|\|school.edu^` |
| `\|\|*keyword*^` | Block any domain with keyword | `\|\|*porn*^` |
| `/regex/` | Block using regex | `/^ad[0-9]+\./` |
| `\|\|domain.com^$client='192.168.1.10'` | Block for specific client | Per-device rules |

## Pre-made Filter Lists

Available in `filters/` folder:

| File | Content |
|------|---------|
| `adult-content.txt` | Porn sites, adult dating |
| `social-media.txt` | TikTok, Discord, Facebook, Instagram, Twitter |
| `gaming.txt` | Steam, Epic Games, Roblox, Battle.net |
| `gambling.txt` | Betting sites, casinos |
| `ads-tracking.txt` | Advertising and tracking domains |

To use: Add to AdGuard Home as custom blocklist.

## Online Blocklists

Add these URLs in AdGuard Home (Filters > DNS blocklists > Add blocklist):

### Recommended Lists

```
# OISD - Comprehensive blocking
https://big.oisd.nl/domainswild

# Steven Black - Unified hosts
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts

# Adult Content (NSFW)
https://nsfw.oisd.nl/domainswild

# Gambling
https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling/hosts
```

## Blocking Applications

### Method 1: Edit Configuration

1. Open `config\apps-to-block.json`
2. Add new application:

```json
{
  "applications": [
    {
      "name": "NewApp",
      "paths": [
        "C:\\Program Files\\NewApp\\newapp.exe",
        "C:\\Program Files (x86)\\NewApp\\newapp.exe"
      ],
      "processNames": ["newapp.exe"]
    }
  ]
}
```

3. Apply changes:

```powershell
.\scripts\firewall-rules.ps1
```

### Method 2: Quick Firewall Rule

Block application immediately:

```powershell
# Block outbound traffic
New-NetFirewallRule -DisplayName "Block-MyApp" `
    -Direction Outbound `
    -Program "C:\Path\To\app.exe" `
    -Action Block

# Block inbound traffic
New-NetFirewallRule -DisplayName "Block-MyApp-In" `
    -Direction Inbound `
    -Program "C:\Path\To\app.exe" `
    -Action Block
```

### Finding Application Paths

```powershell
# Find running process path
Get-Process | Where-Object {$_.ProcessName -like "*steam*"} | Select-Object Path

# Search for executable
Get-ChildItem -Path "C:\Program Files","C:\Program Files (x86)" -Recurse -Filter "*.exe" | 
    Where-Object {$_.Name -like "*discord*"}
```

### Common Application Paths

| Application | Typical Path |
|-------------|--------------|
| Steam | `C:\Program Files (x86)\Steam\steam.exe` |
| Discord | `%APPDATA%\Discord\Discord.exe` |
| Epic Games | `C:\Program Files (x86)\Epic Games\Launcher\...\EpicGamesLauncher.exe` |
| Roblox | `%LOCALAPPDATA%\Roblox\Versions\*\RobloxPlayerBeta.exe` |
| Battle.net | `C:\Program Files (x86)\Battle.net\Battle.net Launcher.exe` |

## Managing Rules

### View Current DNS Rules

In AdGuard Home:
- Filters > DNS blocklists (see active lists)
- Filters > Custom filtering rules (see manual rules)

### View Firewall Rules

```powershell
Get-NetFirewallRule -DisplayName "ParentalControl-*" | Format-Table DisplayName, Enabled, Direction
```

### Remove Specific Rule

```powershell
# Remove firewall rule
Remove-NetFirewallRule -DisplayName "ParentalControl-Block-Steam"

# Or re-run firewall script after editing config
.\scripts\firewall-rules.ps1 -Remove
.\scripts\firewall-rules.ps1
```

### Temporarily Disable Blocking

```powershell
# Disable all ParentalControl firewall rules
Get-NetFirewallRule -DisplayName "ParentalControl-*" | Disable-NetFirewallRule

# Re-enable
Get-NetFirewallRule -DisplayName "ParentalControl-*" | Enable-NetFirewallRule
```

## Testing Rules

### Test DNS Blocking

```powershell
# Should fail if blocked
Resolve-DnsName tiktok.com

# Or use nslookup
nslookup tiktok.com 127.0.0.1
```

### Test in AdGuard Home

1. Go to http://localhost:3000
2. Filters > Check hostname
3. Enter domain to test
4. See if and why it's blocked

### View Query Log

1. Go to http://localhost:3000
2. Query Log
3. Filter by "Blocked" to see what's being blocked

## Tips

1. **Start with categories** - Use Blocked Services in AdGuard Home for quick blocking
2. **Use existing lists** - Don't reinvent the wheel, use proven blocklists
3. **Test changes** - Always verify rules work as expected
4. **Document custom rules** - Add comments in custom-rules.txt
5. **Regular updates** - Enable auto-update for blocklists in AdGuard Home
