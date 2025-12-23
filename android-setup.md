# Android Phone Setup

How to configure parental control on Android phones using Private DNS.

## Overview

Android 9+ supports Private DNS, which can route all DNS queries through a secure DNS server. You can use a public DNS service with parental controls, or your own AdGuard Home if it's accessible.

## Option 1: Use Public DNS Service (Recommended)

### AdGuard Family DNS

Best for parental control - blocks adult content, gambling, etc.

1. Open **Settings**
2. Go to **Network & internet** > **Private DNS**
3. Select **Private DNS provider hostname**
4. Enter: `family.adguard-dns.com`
5. Tap **Save**

### Cloudflare Family DNS

Alternative with malware and adult content blocking:

- Malware only: `security.cloudflare-dns.com`
- Malware + Adult: `family.cloudflare-dns.com`

### CleanBrowsing Family Filter

Strong family filter:

- `family-filter-dns.cleanbrowsing.org`

## Option 2: Use Home AdGuard Home

If your AdGuard Home is accessible from outside your network:

### Requirements
- Static public IP or Dynamic DNS
- Port forwarding for DNS-over-TLS (853)
- TLS certificate configured in AdGuard Home

### Configuration Steps

1. Set up TLS in AdGuard Home (Settings > Encryption)
2. Configure port forwarding on router (TCP 853)
3. On Android, use your domain: `your-domain.com`

Note: This requires advanced networking setup. Public DNS services are easier.

## Option 3: AdGuard App

For more control, install the AdGuard app:

1. Download from https://adguard.com/en/adguard-android/overview.html
2. Enable DNS filtering
3. Choose Family protection or Custom DNS
4. Configure blocked categories

## Verification

### Test DNS Setting

1. Open browser
2. Try to access a known blocked site
3. Should show "blocked" page or fail to load

### Check Current DNS

1. Visit https://www.dnsleaktest.com
2. Run Standard test
3. Verify it shows your chosen DNS provider

## Bypass Prevention

### Lock Settings (Android)

Use Screen Time or Digital Wellbeing:

1. Settings > Digital Wellbeing & parental controls
2. Set up parental controls
3. Create PIN to prevent changes

### Use Family Link (Google)

For stronger control on child's phone:

1. Install Family Link on your phone
2. Set up child's account
3. Control apps, screen time, and more

## DNS Providers Comparison

| Provider | Adult Block | Gambling | Malware | Free |
|----------|-------------|----------|---------|------|
| AdGuard Family | Yes | Yes | Yes | Yes |
| Cloudflare Family | Yes | No | Yes | Yes |
| CleanBrowsing Family | Yes | Yes | Yes | Yes |
| OpenDNS FamilyShield | Yes | No | Yes | Yes |

## Troubleshooting

### DNS Not Working

1. Verify Private DNS is saved correctly
2. Toggle Airplane mode on/off
3. Restart phone

### Apps Bypass DNS

Some apps use their own DNS:
- Use AdGuard app instead of Private DNS
- Or block app entirely via Family Link

### Private DNS Option Missing

Requires Android 9+. For older versions:
- Use AdGuard app
- Or configure per-WiFi network DNS

## Quick Setup Summary

1. Settings > Network & internet > Private DNS
2. Enter: `family.adguard-dns.com`
3. Save and test

This blocks adult content, gambling, and malicious sites on the Android device.
