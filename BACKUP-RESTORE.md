# Záloha a obnovení systému

Tento návod popisuje, jak bezpečně zálohovat a obnovit Windows systém před/po instalaci rodičovské kontroly.

## Proč vytvořit zálohu?

- **Bezpečnost**: Pokud něco pokazíte, můžete vrátit změny
- **Testování**: Můžete testovat nastavení bez obav
- **Bod obnovy**: Rychlé vrácení do funkčního stavu

## Vytvoření zálohy

### Automatická záloha (doporučeno)

```powershell
.\scripts\backup-system.ps1
```

Tento skript vytvoří:
1. **Bod obnovy Windows** - kompletní snapshot systému
2. **Zálohu registru** - důležité registry klíče
3. **Zálohu DNS nastavení** - aktuální DNS konfigurace
4. **Zálohu Firewall pravidel** - všechna firewall pravidla
5. **Zálohu Scheduled Tasks** - naplánované úlohy

### Kde se ukládají zálohy?

```
C:\ProgramData\ParentalControl\Backups\
└── 2024-12-23_14-30-45\
    ├── backup-info.json
    ├── restore-point-info.json
    ├── dns-settings.json
    ├── firewall-rules.csv
    ├── scheduled-tasks.csv
    └── Registry\
        ├── TCP-IP-Parameters.reg
        ├── FirewallPolicy.reg
        └── ...
```

### Ruční záloha (pokročilé)

Pokud preferujete ruční zálohu:

1. **Bod obnovy Windows**:
   - Systém → Ochrana systému → Vytvořit
   - Pojmenujte: "Před rodičovskou kontrolou"

2. **Export registru**:
```powershell
reg export "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" backup-tcp.reg
reg export "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy" backup-firewall.reg
```

3. **Poznamenejte si DNS**:
```powershell
Get-DnsClientServerAddress | Where-Object {$_.ServerAddresses.Count -gt 0}
```

## Obnovení ze zálohy

### Metoda 1: Automatické obnovení (doporučeno)

Obnoví registry, DNS, odstraní ParentalControl komponenty:

```powershell
.\scripts\restore-system.ps1
```

Nebo použijte poslední zálohu:

```powershell
.\scripts\restore-system.ps1 -UseLastBackup
```

### Metoda 2: Jen bod obnovy

Obnoví celý systém z bodu obnovy Windows:

```powershell
.\scripts\restore-system.ps1 -RestorePointOnly
```

Nebo ručně:
1. Stiskněte `Win + R`
2. Spusťte: `rstrui.exe`
3. Vyberte bod obnovy vytvořený před instalací
4. Klikněte **Další** → **Dokončit**

### Metoda 3: Kompletní odstranění

Odstraní všechny komponenty rodičovské kontroly:

```powershell
.\scripts\remove-parental-control.ps1
```

## Co se obnovuje?

| Komponenta | backup-system.ps1 | restore-system.ps1 | remove-parental-control.ps1 | Bod obnovy |
|------------|-------------------|--------------------|-----------------------------|------------|
| Registry klíče | ✅ Zálohuje | ✅ Obnovuje | ⚠️ Částečně | ✅ Obnovuje |
| DNS nastavení | ✅ Zálohuje | ✅ Obnovuje | ❌ Ne | ✅ Obnovuje |
| Firewall pravidla | ✅ Zálohuje | ✅ Odstraňuje PC* | ✅ Odstraňuje | ✅ Obnovuje |
| Scheduled Tasks | ✅ Zálohuje | ✅ Odstraňuje PC* | ✅ Odstraňuje | ✅ Obnovuje |
| AdGuard Home | ❌ Ne | ✅ Zastavuje | ✅ Odstraňuje | ❌ Ne |
| Logy a data | ❌ Ne | ❌ Ponechává | ⚠️ Volitelně | ❌ Ne |

*PC = ParentalControl komponenty

## Častá použití

### Scénář 1: Testování nastavení

```powershell
# 1. Vytvoření zálohy
.\scripts\backup-system.ps1

# 2. Instalace a testování
.\scripts\install-all.ps1
# ... testujete ...

# 3. Pokud nefunguje, obnovení
.\scripts\restore-system.ps1 -UseLastBackup
```

### Scénář 2: Trvalá instalace s možností vrácení

```powershell
# 1. Vytvoření zálohy
.\scripts\backup-system.ps1

# 2. Instalace
.\scripts\install-all.ps1

# 3. Pokud později chcete odstranit
.\scripts\remove-parental-control.ps1
```

### Scénář 3: Katastrofa - systém nefunguje

```powershell
# 1. Restartujte do nouzového režimu (F8 při startu)
# 2. Spusťte bod obnovy
rstrui.exe
# 3. Vyberte bod "Parental Control - Před instalací"
```

## Časté otázky

### Mohu vytvořit více záloh?

Ano, každá záloha se ukládá do samostatného adresáře s časovým razítkem.

### Jak velká je záloha?

- Bod obnovy: 500 MB - 5 GB (závisí na systému)
- Naše záloha: < 10 MB (jen konfigurace)

### Jak dlouho trvá záloha?

- Bod obnovy: 2-5 minut
- Naše záloha: < 30 sekund

### Jak dlouho trvá obnovení?

- Z našeho skriptu: < 1 minuta
- Z bodu obnovy: 5-15 minut

### Mohu smazat staré zálohy?

Ano, bezpečně můžete smazat staré adresáře v:
```
C:\ProgramData\ParentalControl\Backups\
```

### Co když nemám bod obnovy?

Náš zálohovací skript se pokusí vytvořit bod obnovy. Pokud selže:
1. Zapněte System Protection:
   - Systém → Ochrana systému → Konfigurovat
   - Zapnout ochranu systému
2. Spusťte zálohovací skript znovu

### Obnovení přepíše mé současné nastavení?

Ano, obnovení vrátí:
- Registry klíče do stavu zálohy
- DNS nastavení do stavu zálohy
- Odstraní ParentalControl komponenty

**Proto vždy vytvořte zálohu před obnovením!**

## Doporučené pracovní postupy

### Pro testování

1. ✅ Vždy vytvořte zálohu před instalací
2. ✅ Testujte na jednom PC nejdřív
3. ✅ Poznamenejte si, co funguje a co ne
4. ✅ Pokud něco nefunguje, obnovte ze zálohy

### Pro produkční nasazení

1. ✅ Vytvořte zálohu
2. ✅ Otestujte na testovacím PC
3. ✅ Nasaďte na produkční PC dětí
4. ✅ Ponechte zálohy minimálně měsíc

### Pro aktualizace

1. ✅ Vytvořte novou zálohu
2. ✅ Proveďte aktualizaci
3. ✅ Otestujte funkčnost
4. ✅ Pokud OK, můžete smazat starou zálohu

## Bezpečnostní poznámky

- **Nikdy neodstraňujte zálohu, dokud nejste 100% jistí, že vše funguje**
- Zálohy obsahují citlivá data (registry klíče) - chraňte je
- Pravidelně kontrolujte, že máte aktuální zálohu
- Bod obnovy zabírá místo - Windows automaticky maže staré body

## Řešení problémů

### Zálohovací skript selhal

- Zkontrolujte, zda máte dostatek místa na disku
- Zkontrolujte, zda je zapnuta System Protection
- Spusťte PowerShell jako administrátor

### Obnovení nefunguje

- Zkontrolujte, zda zálohovací adresář existuje
- Zkuste použít bod obnovy místo našeho skriptu
- Kontaktujte podporu (nebo mě)

### Registry se neobnovil

- Zkontrolujte, zda máte administrátorská práva
- Zkuste importovat .reg soubory ručně
- Použijte bod obnovy pro úplné obnovení

