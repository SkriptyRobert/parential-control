# DNS Filters Overview

Complete list of all active DNS blocklists in AdGuard Home configuration.

## Security Filters (Malware, Phishing, Scam)

| Filter | Source | Purpose |
|--------|--------|---------|
| Dandelion Sprout's Anti-Malware | GitHub | Blocks malware domains |
| Phishing Army Extended | phishing.army | Blocks phishing sites |
| Spam404 - Scam and Phishing | GitHub | Blocks scam and phishing |
| Scam Blocklist | GitHub | Blocks scam domains |
| URLhaus Malware Domains | abuse.ch | Active malware domains |
| Phishing Database Active | GitHub | Active phishing domains |

## Ads and Tracking Filters

| Filter | Source | Purpose |
|--------|--------|---------|
| AdGuard DNS filter | AdGuard | General ad blocking |
| AdAway Default | adaway.org | Mobile and desktop ads |
| Steven Black's Unified | GitHub | Unified hosts list |
| EasyList | firebog.net | World-wide ad blocking |
| EasyPrivacy | firebog.net | Tracking protection |
| Prigent Ads | firebog.net | Additional ads |
| Prigent Malware | firebog.net | Malware protection |
| AdGuard Tracking | AdGuard | Tracking protection |
| AdGuard Mobile Ads | AdGuard | Mobile ad blocking |

## Content Filters

| Filter | Source | Purpose |
|--------|--------|---------|
| Steven Black - Porn | GitHub | Adult content |
| OISD NSFW | oisd.nl | Adult content |
| Steven Black - Gambling | GitHub | Gambling sites |

## Custom Filters (Local)

Located in `filters/` folder:
- `adult-content.txt` - Adult/porn sites
- `social-media.txt` - Social networks
- `gaming.txt` - Gaming platforms
- `gambling.txt` - Gambling sites
- `ads-tracking.txt` - Ads and tracking
- `custom-rules.txt` - Your custom rules

## Total Active Filters

- **Security**: 6 filters (malware, phishing, scam)
- **Ads/Tracking**: 9 filters (world-wide coverage)
- **Content**: 2 filters (adult, gambling)
- **Custom**: 6 local files

**Total: 23+ active blocklists**

## Filter Updates

All filters are set to auto-update every 24 hours in AdGuard Home.

## Verification

To verify filters are active:
1. Open http://localhost:3000
2. Go to Filters > DNS blocklists
3. Check all filters show "Enabled" and have recent update times

