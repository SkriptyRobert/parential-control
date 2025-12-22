# Jak přidávat blokace - Podrobný návod

## 📱 Blokování aplikací (Windows Firewall)

### Najít název procesu aplikace

1. Spusťte aplikaci, kterou chcete blokovat
2. Otevřete **Task Manager** (Ctrl+Shift+Esc)
3. Přejděte na záložku **Podrobnosti**
4. Najděte aplikaci a poznamenejte si **Název** (např. `fortnite.exe`)
5. Klikněte pravým tlačítkem → **Otevřít umístění souboru**
6. Zkopírujte **celou cestu** k .exe souboru

### Přidání do konfigurace

1. Otevřete `config\apps-to-block.json`
2. Přidejte nový objekt do pole `applications`:

```json
{
  "name": "Název aplikace",
  "paths": [
    "C:\\Cesta\\k\\aplikaci\\aplikace.exe"
  ],
  "processNames": ["aplikace.exe"]
}
```

### Příklady

#### Fortnite
```json
{
  "name": "Fortnite",
  "paths": [
    "C:\\Program Files\\Epic Games\\Fortnite\\FortniteGame\\Binaries\\Win64\\FortniteClient-Win64-Shipping.exe"
  ],
  "processNames": ["FortniteClient-Win64-Shipping.exe"]
}
```

#### Minecraft
```json
{
  "name": "Minecraft",
  "paths": [
    "$env:APPDATA\\.minecraft\\runtime\\*\\minecraft.exe"
  ],
  "processNames": ["minecraft.exe", "javaw.exe"]
}
```

#### Valorant
```json
{
  "name": "Valorant",
  "paths": [
    "C:\\Riot Games\\VALORANT\\live\\VALORANT.exe"
  ],
  "processNames": ["VALORANT.exe", "RiotClientServices.exe"]
}
```

### Aplikace změn

Po úpravě `apps-to-block.json` spusťte:

```powershell
.\scripts\firewall-rules.ps1
```

## 🌐 Blokování webových stránek (AdGuard Home)

### Metoda 1: Přes webové rozhraní (nejjednodušší)

1. Otevřete `http://localhost:3000`
2. Přihlaste se
3. Přejděte na **Filters** → **Custom filtering rules**
4. Přidejte pravidlo v AdGuard syntaxi:
   - `||domena.com^` - blokuje celou doménu
   - `||domena.com^$important` - vynucené blokování
   - `@@||domena.com^` - whitelist (povolí doménu)
5. Klikněte **Save**

### Metoda 2: Přes konfigurační soubor

1. Otevřete `adguard-config\AdGuardHome.yaml`
2. Najděte sekci `user_rules:`
3. Přidejte řádek s pravidlem:
```yaml
user_rules:
  - "||facebook.com^"
  - "||instagram.com^"
  - "||youtube.com^"
```
4. Restartujte AdGuard Home:
```powershell
docker-compose restart
```

### AdGuard syntaxe pravidel

- `||example.com^` - Blokuje celou doménu a všechny subdomény
- `|https://example.com|` - Blokuje přesnou URL
- `||example.com^$important` - Vynucené blokování (přepíše whitelist)
- `@@||example.com^` - Whitelist (povolí doménu)
- `||example.com^$denyallow=allowed.example.com` - Blokuje vše kromě povolené subdomény

### Příklady blokování

#### Sociální sítě
```yaml
user_rules:
  - "||facebook.com^"
  - "||instagram.com^"
  - "||twitter.com^"
  - "||x.com^"
  - "||snapchat.com^"
  - "||tiktok.com^"
```

#### Herní stránky
```yaml
user_rules:
  - "||twitch.tv^"
  - "||steamcommunity.com^"
  - "||epicgames.com^"
```

#### Konkrétní stránky
```yaml
user_rules:
  - "||example.com/bad-page^"
  - "|https://example.com/specific-url|"
```

## 📋 Použití pravidel z internetu

### AdGuard filtry (už jsou přednastavené)

AdGuard Home už má přednastavené oficiální filtry:
- AdGuard DNS filter
- AdAway
- StevenBlack
- Pornografie
- Gambling
- Sociální sítě
- Tracking

### Přidání dalších AdGuard filtrů

1. Otevřete `http://localhost:3000`
2. **Filters** → **DNS blocklists**
3. Klikněte **Add blocklist**
4. Vložte URL filtru, např.:
   - `https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/SpywareFilter/sections/tracking.txt`
5. Klikněte **Save**

### Použití jiných DNS filtrů

Můžete použít jakýkoliv filtr v AdGuard syntaxi:

**Populární zdroje:**
- [AdGuard Filters](https://github.com/AdguardTeam/AdguardFilters)
- [OISD](https://oisd.nl/)
- [StevenBlack/hosts](https://github.com/StevenBlack/hosts)

**Příklad přidání OISD filtru:**
1. Webové rozhraní → **Filters** → **DNS blocklists**
2. **Add blocklist**
3. URL: `https://dbl.oisd.nl/`
4. **Save**

### Windows Firewall pravidla z internetu

Pokud najdete Windows Firewall exporty z jiných zdrojů, můžete je použít, ale:

1. **Formát musí být JSON** jako náš `apps-to-block.json`
2. Nebo můžete použít PowerShell příkazy přímo:
```powershell
New-NetFirewallRule -DisplayName "Block-App" -Direction Outbound -Program "C:\Path\app.exe" -Action Block
```

## ⏰ Časové limity pro aplikace

**Aktuálně**: Časové limity jsou **globální** (pro celý PC), ne per aplikace.

**Workaround**: Můžete použít Scheduled Tasks pro spuštění/ukončení blokování:

```powershell
# Blokovat aplikaci od 20:00
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `"New-NetFirewallRule -DisplayName 'Block-Fortnite' -Direction Outbound -Program 'C:\Path\fortnite.exe' -Action Block`""
$trigger = New-ScheduledTaskTrigger -Daily -At "20:00"
Register-ScheduledTask -TaskName "Block-Fortnite-Evening" -Action $action -Trigger $trigger
```

## 🔄 Aktualizace pravidel

### AdGuard filtry
- Automaticky se aktualizují každých 24 hodin
- Nebo ručně: Webové rozhraní → **Filters** → **Check for updates**

### Firewall pravidla
- Po změně `apps-to-block.json` vždy spusťte:
```powershell
.\scripts\firewall-rules.ps1
```

## 🧪 Testování blokování

### Test webové stránky
1. Zkuste otevřít blokovanou stránku v prohlížeči
2. Měla by se zobrazit AdGuard blokovací stránka
3. Zkontrolujte logy: Webové rozhraní → **Query log**

### Test aplikace
1. Zkuste spustit blokovanou aplikaci
2. Aplikace by se měla spustit, ale neměla by mít internet
3. Zkontrolujte Firewall logy:
```powershell
Get-NetFirewallRule -DisplayName "ParentalControl-*" | Get-NetFirewallApplicationFilter
```

## 💡 Tipy

- **Wildcard cesty**: Použijte `*` pro proměnné cesty, např. `$env:APPDATA\App\*\app.exe`
- **Více procesů**: Některé aplikace mají více procesů - přidejte všechny do `processNames`
- **Testování**: Vždy nejdřív otestujte na testovacím PC
- **Záloha**: Před velkými změnami si zálohujte konfigurační soubory

## 🆘 Řešení problémů

### Aplikace stále funguje
- Zkontrolujte, zda je správný název procesu (Task Manager)
- Zkontrolujte, zda je správná cesta (může být jiná na jiném PC)
- Zkontrolujte Firewall pravidla: `Get-NetFirewallRule -DisplayName "ParentalControl-*"`

### Webová stránka se stále načítá
- Zkontrolujte AdGuard logy
- Zkontrolujte, zda DNS je nastaveno na `127.0.0.1`
- Zkuste vymazat cache prohlížeče

### Pravidla se neaktualizují
- Restartujte AdGuard Home: `docker-compose restart`
- Zkontrolujte syntaxi pravidel (musí být správná AdGuard syntaxe)

