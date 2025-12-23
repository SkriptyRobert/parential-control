# Rodičovská kontrola - Komplexní řešení

Kompletní řešení rodičovské kontroly pro Windows PC a Android telefony s využitím AdGuard Home, Windows Firewall, GPO policies a PowerShell skriptů pro časovou kontrolu.

## Přehled

Toto řešení poskytuje:

- **DNS filtrování** přes AdGuard Home (blokování nevhodného obsahu)
- **Blokování aplikací** přes Windows Firewall (Steam, Discord, atd.)
- **Časovou kontrolu** přes PowerShell skripty (noční vypínání, denní limity, rozvrh)
- **GPO policies** pro prevenci obcházení nastavení
- **Nezávislé řešení** - každé PC dítěte má vlastní instanci

## Požadavky

- Windows 10/11 Pro (pro GPO policies) nebo Windows 10/11 Home (omezené GPO)
- Docker Desktop nainstalovaný a spuštěný
- Administrátorská práva pro instalaci
- PowerShell 5.1 nebo novější

## Struktura projektu

```
Parential-Control/
├── docker-compose.yml          # AdGuard Home kontejner
├── adguard-config/             # AdGuard Home konfigurace
├── scripts/                    # PowerShell skripty
│   ├── install-all.ps1        # Hlavní instalační skript
│   ├── install-adguard.ps1    # Instalace AdGuard Home
│   ├── firewall-rules.ps1      # Windows Firewall pravidla
│   ├── night-shutdown.ps1     # Noční vypínání
│   ├── daily-limit.ps1        # Denní limity
│   ├── schedule-control.ps1   # Časový rozvrh
│   ├── setup-scheduled-tasks.ps1  # Nastavení úloh
│   └── apply-gpo-policies.ps1 # Aplikace GPO
├── gpo/                       # GPO policies
├── config/                    # Konfigurační soubory
│   ├── apps-to-block.json     # Seznam aplikací
│   └── time-limits.json       # Časové limity
└── android-setup.md           # Návod pro Android
```

## Rychlá instalace

### 1. Příprava

1. Stáhněte nebo naklonujte tento projekt do adresáře na Windows PC
2. **Nainstalujte [Docker Desktop](https://www.docker.com/products/docker-desktop)** pokud ještě nemáte a **spusťte ho**
3. Spusťte PowerShell jako **administrátor** (pravý klik → Spustit jako správce)
4. (Volitelné) Pokud chybí Git, nainstalujte jej:\
   ```powershell
   .\scripts\install-git.ps1
   ```

### 2. Vytvoření zálohy (doporučeno)

**Důrazně doporučujeme vytvořit zálohu systému před instalací!**

```powershell
.\scripts\backup-system.ps1
```

Tento skript vytvoří:
- Bod obnovy Windows
- Zálohu registru
- Zálohu DNS nastavení
- Zálohu Firewall pravidel

### 3. Instalace všech komponent

```powershell
cd C:\cesta\k\projektu\Parential-Control
.\scripts\install-all.ps1
```

**Poznámka**: Skript vás provede instalací všech komponent. Můžete také instalovat jednotlivé části samostatně (viz níže).

Tento skript nainstaluje:
- AdGuard Home v Docker kontejneru
- Windows Firewall pravidla pro blokování aplikací
- GPO policies (s potvrzením)
- Scheduled Tasks pro časovou kontrolu

### 3. Dokončení nastavení AdGuard Home

1. Otevřete prohlížeč a přejděte na `http://localhost:3000`
2. Dokončete počáteční nastavení (vytvořte admin účet)
3. AdGuard Home bude automaticky používat přednastavené filtry

### 4. Nastavení DNS na PC

1. Otevřete **Nastavení sítě** → **Změnit možnosti adaptéru**
2. Klikněte pravým tlačítkem na aktivní připojení → **Vlastnosti**
3. Vyberte **Internet Protocol Version 4 (TCP/IPv4)** → **Vlastnosti**
4. Nastavte **Použít následující adresy DNS serverů**:
   - **Preferovaný DNS server**: `127.0.0.1`
   - **Alternativní DNS server**: `8.8.8.8`
5. Potvrďte a zavřete

### 5. Konfigurace časových limitů

Upravte soubor `config\time-limits.json` podle vašich potřeb:

```json
{
  "dailyLimit": {
    "enabled": true,
    "hours": 2,
    "warningAtMinutes": 15
  },
  "nightShutdown": {
    "enabled": true,
    "startTime": "00:00",
    "endTime": "06:00"
  },
  "schedule": {
    "enabled": true,
    "allowedWindows": [...]
  }
}
```

### 6. Konfigurace blokovaných aplikací

Upravte soubor `config\apps-to-block.json` a přidejte/odeberte aplikace podle potřeby.

### 7. Nastavení Android telefonů

Postupujte podle návodu v `android-setup.md`.

## Manuální instalace komponent

### Pouze AdGuard Home

```powershell
.\scripts\install-adguard.ps1
```

### Pouze Firewall pravidla

```powershell
.\scripts\firewall-rules.ps1
```

### Pouze Scheduled Tasks

```powershell
.\scripts\setup-scheduled-tasks.ps1
```

### Pouze GPO Policies

```powershell
.\scripts\apply-gpo-policies.ps1
```

## Funkce

### DNS Filtrování (AdGuard Home)

- Blokuje pornografii, gambling, násilný obsah
- Blokuje sociální sítě (TikTok, Discord, Facebook, Instagram, atd.)
- Blokuje reklamy a tracking
- Logování všech DNS dotazů
- Webové rozhraní pro správu (`http://localhost:3000`)
- **Přidání webu**: Přes webové rozhraní nebo přidáním do `user_rules` v `adguard-config/AdGuardHome.yaml`

### Blokování aplikací (Windows Firewall)

- Automatické blokování podle konfigurace
- Podpora wildcard cest
- Blokování odchozího i příchozího provozu
- Snadné přidávání/odebírání aplikací
- **Přidání aplikace**: Upravte `config/apps-to-block.json` a spusťte `.\scripts\firewall-rules.ps1`

### Časová kontrola

#### Noční vypínání
- Automatické vypnutí PC po půlnoci a před 6:00
- Kontrola každých 15 minut
- Upozornění před vypnutím

#### Denní limity
- Sledování času použití PC
- Upozornění při blížícím se limitu
- Automatické vypnutí po dosažení limitu
- Kontrola každých 5 minut

#### Časový rozvrh
- Povolené časové okno pro každý den
- Automatické vypnutí mimo povolené okno
- Kontrola každých 5 minut

### GPO Policies

- Blokování změny DNS nastavení
- Blokování instalace aplikací
- Blokování změny času
- Blokování přístupu k registru
- A další bezpečnostní opatření

## Správa a údržba

### Kontrola Scheduled Tasks

```powershell
Get-ScheduledTask -TaskName "ParentalControl-*" | Format-Table -AutoSize
```

### Kontrola Firewall pravidel

```powershell
Get-NetFirewallRule -DisplayName "ParentalControl-*" | Format-Table -AutoSize
```

### Kontrola AdGuard Home

- Webové rozhraní: `http://localhost:3000`
- Logy: `adguard-config\work\querylog.json`

### Kontrola logů časové kontroly

```powershell
# Noční vypínání
Get-Content "$env:ProgramData\ParentalControl\night-shutdown.log" -Tail 20

# Denní limity
Get-Content "$env:ProgramData\ParentalControl\daily-limit.log" -Tail 20

# Časový rozvrh
Get-Content "$env:ProgramData\ParentalControl\schedule-control.log" -Tail 20
```

### Odstranění firewall pravidel

```powershell
.\scripts\firewall-rules.ps1 -Remove
```

### Odstranění GPO policies

```powershell
.\scripts\apply-gpo-policies.ps1 -Remove
```

### Odstranění Scheduled Tasks

```powershell
Unregister-ScheduledTask -TaskName "ParentalControl-*" -Confirm:$false
```

## Záloha a obnovení systému

### Vytvoření zálohy

Před instalací vytvořte zálohu systému:

```powershell
.\scripts\backup-system.ps1
```

### Obnovení ze zálohy

Pro obnovení systému do stavu před instalací:

```powershell
.\scripts\restore-system.ps1
```

Nebo použijte poslední zálohu:

```powershell
.\scripts\restore-system.ps1 -UseLastBackup
```

### Kompletní odstranění rodičovské kontroly

Pro úplné odstranění všech komponent:

```powershell
.\scripts\remove-parental-control.ps1
```

## Řešení problémů

### AdGuard Home se nespustí

1. Zkontrolujte, zda Docker běží: `docker ps`
2. Zkontrolujte logy: `docker-compose logs adguard`
3. Zkontrolujte, zda port 53 není používán jinou aplikací

### Firewall pravidla nefungují

1. Zkontrolujte, zda jsou pravidla vytvořena: `Get-NetFirewallRule -DisplayName "ParentalControl-*"`
2. Zkontrolujte, zda jsou pravidla povolena: `Get-NetFirewallRule -DisplayName "ParentalControl-*" | Select-Object DisplayName, Enabled`
3. Zkontrolujte, zda aplikace běží pod správným procesem

### Časová kontrola nefunguje

1. Zkontrolujte, zda jsou Scheduled Tasks spuštěny: `Get-ScheduledTask -TaskName "ParentalControl-*"`
2. Zkontrolujte logy v `$env:ProgramData\ParentalControl\`
3. Zkontrolujte, zda jsou skripty spouštěny jako SYSTEM

### DNS nefunguje po nastavení na 127.0.0.1

1. Zkontrolujte, zda AdGuard Home běží: `docker ps`
2. Zkontrolujte, zda AdGuard Home naslouchá na portu 53: `netstat -an | findstr :53`
3. Zkontrolujte firewall - port 53 musí být otevřený

## Bezpečnostní poznámky

- **Nikdy neaplikujte GPO policies na administrátorský účet!**
- Před aplikací GPO policies si vytvořte zálohu registru
- Testujte na testovacím PC před nasazením na produkční PC dětí
- Udržujte Docker a AdGuard Home aktualizované
- Pravidelně kontrolujte logy pro podezřelou aktivitu

## Omezení

- **Android telefony**: Pokud PC s AdGuard Home není zapnuté, telefon nebude mít DNS (což může být i výhoda)
- **GPO policies**: Některé funkce vyžadují Windows Pro (Home má omezené GPO)
- **Časová kontrola**: Funguje pouze když je PC zapnuté a někdo je přihlášený

## Budoucí vylepšení

- Cloud-hosted server pro centrální správu (jak plánujete)
- Webové rozhraní pro správu časových limitů
- Notifikace rodičům o aktivitě dětí
- Pokročilejší monitoring a reporty

## Remote Session (RDP, PSRemoting)

Pro instalaci a správu přes vzdálené připojení viz `REMOTE-SESSION.md`.

**Rychlý tip pro remote session:**
```powershell
# Záloha bez bodu obnovy (doporučeno pro remote session)
.\scripts\backup-system.ps1 -SkipRestorePoint
```

## Podpora

Pro problémy nebo dotazy:
1. Zkontrolujte logy v `$env:ProgramData\ParentalControl\`
2. Zkontrolujte AdGuard Home logy
3. Zkontrolujte Windows Event Viewer pro chyby

## Licence

Tento projekt je poskytován "tak jak je" bez záruk. Používejte na vlastní riziko.

