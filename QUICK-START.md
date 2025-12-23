# Rychlý start - Rodičovská kontrola

## Co potřebujete před instalací

1. ✅ **PowerShell jako administrátor**
   - Pravý klik na PowerShell → "Spustit jako správce"

2. ⚡ **AdGuard Home** - dvě možnosti:
   - **Windows Service** (doporučeno pro Win10) - bez Dockeru, funguje jako služba
   - **Docker** - vyžaduje Docker Desktop

**Poznámka**: Instalační skript automaticky detekuje, co máte k dispozici.

## Instalace (4 kroky)

### Krok 1: Zkopírujte projekt
```powershell
# Pokud máte projekt v Downloads nebo jinde
cd C:\Users\Administrator\Documents\Cursor\Parential-Control
```

### Krok 1b: (Volitelné) Nainstalujte Git, pokud chybí
```powershell
.\scripts\install-git.ps1
```

### Krok 2: Vytvořte zálohu (doporučeno!)
```powershell
.\scripts\backup-system.ps1
```

Tento krok vytvoří bod obnovy Windows a zálohuje důležité nastavení. Pokud něco pokazíte, můžete snadno vrátit změny.

### Krok 3: Spusťte instalaci
```powershell
.\scripts\install-all.ps1
```

Skript vás provede:
- ✅ Instalací AdGuard Home (Service nebo Docker - dle dostupnosti)
- ✅ Nastavením Firewall pravidel
- ✅ Vytvořením Scheduled Tasks
- ⚠️ GPO policies (bude se ptát - můžete přeskočit)

**Volitelné parametry:**
```powershell
# Vynutit Windows Service (bez Dockeru)
.\scripts\install-all.ps1 -AdGuardMode Service

# Vynutit Docker
.\scripts\install-all.ps1 -AdGuardMode Docker
```

### Krok 4: Dokončete AdGuard Home
1. Otevřete prohlížeč: `http://localhost:3000`
2. Vytvořte admin účet (zapamatujte si heslo!)
3. AdGuard Home je připraven

## Nastavení DNS na PC

1. **Nastavení** → **Síť a internet** → **Změnit možnosti adaptéru**
2. Pravý klik na aktivní připojení → **Vlastnosti**
3. **Internet Protocol Version 4 (TCP/IPv4)** → **Vlastnosti**
4. **Použít následující adresy DNS serverů**:
   - Preferovaný: `127.0.0.1`
   - Alternativní: `8.8.8.8`
5. **OK** → **OK**

## Přidání aplikace k blokování

### Příklad: Blokovat Fortnite

1. Otevřete `config\apps-to-block.json`
2. Najděte sekci `"applications"` a přidejte:
```json
{
  "name": "Fortnite",
  "paths": [
    "C:\\Program Files\\Epic Games\\Fortnite\\FortniteGame\\Binaries\\Win64\\FortniteClient-Win64-Shipping.exe"
  ],
  "processNames": ["FortniteClient-Win64-Shipping.exe"]
}
```
3. Spusťte znovu firewall skript:
```powershell
.\scripts\firewall-rules.ps1
```

## Přidání webu k blokování

### Metoda 1: Přes webové rozhraní (doporučeno)
1. Otevřete `http://localhost:3000`
2. Přihlaste se
3. **Filters** → **Custom filtering rules**
4. Přidejte pravidlo, např.: `||facebook.com^`
5. **Save**

### Metoda 2: Přes konfigurační soubor
1. Otevřete `adguard-config\AdGuardHome.yaml`
2. Najděte sekci `user_rules:`
3. Přidejte řádek, např.: `  - "||facebook.com^"`
4. Restartujte AdGuard Home:
```powershell
docker-compose restart
```

## Časové limity

Upravte `config\time-limits.json`:

```json
{
  "dailyLimit": {
    "enabled": true,
    "hours": 2,              // Max 2 hodiny denně
    "warningAtMinutes": 15   // Upozornění 15 min před koncem
  },
  "nightShutdown": {
    "enabled": true,
    "startTime": "00:00",    // Zakázáno od půlnoci
    "endTime": "06:00"       // Do 6:00 ráno
  }
}
```

Po změně není potřeba nic restartovat - skripty načtou nové nastavení automaticky.

## Kontrola, že vše funguje

### AdGuard Home
```powershell
docker ps
# Měli byste vidět "adguard-home" kontejner
```

### Firewall pravidla
```powershell
Get-NetFirewallRule -DisplayName "ParentalControl-*" | Select-Object DisplayName, Enabled
```

### Scheduled Tasks
```powershell
Get-ScheduledTask -TaskName "ParentalControl-*" | Format-Table -AutoSize
```

## Odstranění blokace aplikace

1. Otevřete `config\apps-to-block.json`
2. Odstraňte záznam aplikace
3. Spusťte:
```powershell
.\scripts\firewall-rules.ps1 -Remove
.\scripts\firewall-rules.ps1
```

## Problémy?

### Docker neběží
- Spusťte Docker Desktop
- Počkejte, až ikona bude zelená

### AdGuard Home se nespustí
```powershell
docker-compose logs adguard
```

### Firewall pravidla nefungují
- Zkontrolujte, zda aplikace běží pod správným názvem procesu
- Použijte Task Manager → Podrobnosti → Najděte název .exe souboru

### Časová kontrola nefunguje
- Zkontrolujte Scheduled Tasks:
```powershell
Get-ScheduledTask -TaskName "ParentalControl-*" | Get-ScheduledTaskInfo
```

## Tipy

- **Logy**: Všechny logy jsou v `C:\ProgramData\ParentalControl\`
- **AdGuard logy**: Webové rozhraní → Query log
- **Test blokování**: Zkuste otevřít blokovanou stránku v prohlížeči
- **Test aplikace**: Zkuste spustit blokovanou aplikaci - měla by být zablokována

