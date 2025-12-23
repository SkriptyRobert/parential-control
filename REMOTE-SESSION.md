# Práce s remote session (RDP, PSRemoting)

Tento dokument popisuje, jak pracovat s rodičovskou kontrolou přes vzdálené připojení.

## Podporované typy remote session

✅ **RDP (Remote Desktop Protocol)** - Plně podporováno  
✅ **PowerShell Remoting (PSRemoting)** - Plně podporováno  
✅ **SSH** - Podporováno (s omezeními)  
⚠️ **TeamViewer, AnyDesk** - Většinou funguje jako lokální session

## Záloha systému přes remote session

### Běžné použití

```powershell
# Záloha funguje normálně, ale vytváření bodu obnovy může selhat
.\scripts\backup-system.ps1
```

**Co se stane:**
- ✅ Registry záloha - funguje plně
- ✅ DNS nastavení - funguje plně
- ✅ Firewall pravidla - funguje plně
- ✅ Scheduled Tasks - funguje plně
- ⚠️ Bod obnovy Windows - může selhat v remote session

### Přeskočení bodu obnovy

Pokud vytváření bodu obnovy selže nebo chcete zálohu urychlit:

```powershell
.\scripts\backup-system.ps1 -SkipRestorePoint
```

### Vytvoření bodu obnovy ručně (doporučeno)

Pro jistotu vytvořte bod obnovy ručně před spuštěním skriptu:

**Metoda 1: PowerShell**
```powershell
Enable-ComputerRestore -Drive "$env:SystemDrive\"
Checkpoint-Computer -Description "Před rodičovskou kontrolou" -RestorePointType "MODIFY_SETTINGS"
```

**Metoda 2: GUI (přes RDP)**
1. Otevřete **Systém** → **Ochrana systému**
2. Klikněte **Vytvořit**
3. Pojmenujte: "Před rodičovskou kontrolou"
4. Klikněte **Vytvořit**

**Metoda 3: WMI (funguje v remote session)**
```powershell
$wmi = Get-WmiObject -List -Namespace root\default | Where-Object {$_.Name -eq "SystemRestore"}
$wmi.CreateRestorePoint("Před rodičovskou kontrolou", 0, 100)
```

## Instalace přes remote session

### Standardní instalace

```powershell
# Připojte se přes RDP nebo PSRemoting
Enter-PSSession -ComputerName PC-DITETE -Credential Admin

# Přejděte do adresáře projektu
cd C:\Path\To\Parential-Control

# Vytvořte zálohu (doporučeno přeskočit bod obnovy)
.\scripts\backup-system.ps1 -SkipRestorePoint

# Instalujte
.\scripts\install-all.ps1
```

### PSRemoting instalace

```powershell
# Z vašeho PC se připojte k PC dítěte
$session = New-PSSession -ComputerName PC-DITETE -Credential (Get-Credential)

# Zkopírujte projekt na vzdálený PC
Copy-Item -Path "C:\Local\Parential-Control" -Destination "C:\Remote\Parential-Control" -ToSession $session -Recurse

# Spusťte instalaci na vzdáleném PC
Invoke-Command -Session $session -ScriptBlock {
    cd C:\Remote\Parential-Control
    .\scripts\backup-system.ps1 -SkipRestorePoint
    .\scripts\install-all.ps1 -SkipGPO  # GPO vyžaduje restart
}

# Ukončete session
Remove-PSSession $session
```

## Omezení a řešení

### 1. Checkpoint-Computer nefunguje v remote session

**Problém:** `Checkpoint-Computer` může selhat přes RDP/PSRemoting

**Řešení:**
- Použijte parametr `-SkipRestorePoint`
- Nebo vytvořte bod obnovy ručně před instalací (viz výše)
- Skript automaticky zkusí použít WMI metodu jako fallback

### 2. Docker Desktop může vyžadovat restart

**Problém:** Docker Desktop může vyžadovat restart po instalaci

**Řešení:**
```powershell
# Po instalaci Docker Desktop restartujte vzdálený PC
Restart-Computer -ComputerName PC-DITETE -Force
```

### 3. GPO policies vyžadují restart

**Problém:** Některé GPO policies se aplikují až po restartu

**Řešení:**
```powershell
# Aplikujte GPO a restartujte
.\scripts\apply-gpo-policies.ps1
Restart-Computer -Force
```

### 4. Interaktivní dialogy v remote session

**Problém:** Některé skripty se ptají na potvrzení (Y/N)

**Řešení:**
```powershell
# Přeskočte GPO při automatické instalaci
.\scripts\install-all.ps1 -SkipGPO

# Nebo použijte parametry pro přeskočení dialogů
# (budeme implementovat v budoucnu)
```

## Nejlepší postupy pro remote session

### 1. Příprava před připojením

```powershell
# Na vašem PC (admin PC)
# 1. Zkopírujte projekt na USB nebo sdílenou složku
# 2. Připravte si přihlašovací údaje
```

### 2. Připojení a instalace

```powershell
# Připojte se přes RDP
mstsc /v:PC-DITETE

# V remote session:
# 1. Zkopírujte projekt z USB/sdílené složky
# 2. Otevřete PowerShell jako administrátor
# 3. Spusťte zálohu (přeskočte bod obnovy)
.\scripts\backup-system.ps1 -SkipRestorePoint

# 4. Volitelně vytvořte bod obnovy ručně přes GUI
# Systém → Ochrana systému → Vytvořit

# 5. Spusťte instalaci
.\scripts\install-all.ps1
```

### 3. Po instalaci

```powershell
# Restartujte PC
Restart-Computer -Force

# Odpojte se a znovu se připojte
# Ověřte, že vše funguje
```

## PowerShell Remoting pro dávkovou instalaci

Pro instalaci na více PC najednou:

```powershell
# Seznam PC
$computers = @("PC-DITE1", "PC-DITE2", "PC-DITE3")

# Připravte credentials
$cred = Get-Credential -Message "Zadejte admin credentials"

# Instalace na všechny PC
foreach ($pc in $computers) {
    Write-Host "`nInstalace na $pc..." -ForegroundColor Cyan
    
    # Vytvoření session
    $session = New-PSSession -ComputerName $pc -Credential $cred -ErrorAction SilentlyContinue
    
    if ($session) {
        # Zkopírování projektu
        Copy-Item -Path "C:\Parential-Control" -Destination "C:\" -ToSession $session -Recurse -Force
        
        # Instalace
        Invoke-Command -Session $session -ScriptBlock {
            cd C:\Parential-Control
            
            # Záloha (bez bodu obnovy)
            .\scripts\backup-system.ps1 -SkipRestorePoint
            
            # Instalace
            .\scripts\install-all.ps1 -SkipGPO
        }
        
        # Restart
        Write-Host "Restartuji $pc..." -ForegroundColor Yellow
        Restart-Computer -ComputerName $pc -Force -ErrorAction SilentlyContinue
        
        Remove-PSSession $session
        
        Write-Host "Hotovo: $pc" -ForegroundColor Green
    } else {
        Write-Warning "Nelze se připojit k $pc"
    }
}
```

## Časté problémy

### Bod obnovy se nevytvoří

```
Error: Checkpoint-Computer : A system restore point cannot be created because one has already been created within the past 24 hours.
```

**Řešení:** Windows limituje vytváření bodů obnovy (max 1x za 24h). Použijte:
- `-SkipRestorePoint` parametr
- Nebo počkejte 24 hodin
- Nebo vytvořte bod obnovy ručně přes GUI

### Docker není dostupný v remote session

```
Error: docker : The term 'docker' is not recognized
```

**Řešení:** Docker Desktop není plně dostupný v některých remote sessions:
1. Nainstalujte Docker Desktop ručně přes RDP GUI
2. Restartujte PC
3. Pak spusťte instalační skripty

### Permission denied v remote session

```
Error: Access to the path is denied
```

**Řešení:**
- Ujistěte se, že jste připojeni jako administrátor
- Použijte `Run as Administrator` při otevírání PowerShell
- Zkontrolujte, že máte práva k adresáři

## Bezpečnost remote session

### Důležité bezpečnostní poznámky

1. **Vždy používejte šifrované připojení** (RDP s TLS, PSRemoting s SSL)
2. **Neukládejte hesla v skriptech** - použijte `Get-Credential`
3. **Zavřete session po dokončení** - `Remove-PSSession`
4. **Ověřte identitu PC** před instalací
5. **Záloha je kritická** - vždy vytvořte zálohu před instalací

### Doporučení pro PowerShell Remoting

```powershell
# Povolte PSRemoting (na vzdáleném PC)
Enable-PSRemoting -Force

# Povolte pouze konkrétní uživatele (bezpečnější)
Set-PSSessionConfiguration -Name Microsoft.PowerShell -ShowSecurityDescriptorUI

# Použijte SSL pro šifrované připojení
New-PSSession -ComputerName PC -UseSSL -Credential $cred
```

## Shrnutí

| Funkce | Lokální | RDP | PSRemoting |
|--------|---------|-----|------------|
| Záloha registru | ✅ | ✅ | ✅ |
| Záloha DNS | ✅ | ✅ | ✅ |
| Záloha Firewall | ✅ | ✅ | ✅ |
| Bod obnovy | ✅ | ⚠️ | ⚠️ |
| Instalace AdGuard | ✅ | ✅ | ⚠️* |
| Firewall pravidla | ✅ | ✅ | ✅ |
| Scheduled Tasks | ✅ | ✅ | ✅ |
| GPO policies | ✅ | ✅ | ✅ |

*AdGuard vyžaduje Docker Desktop, který může vyžadovat GUI instalaci

## Doporučený workflow pro remote session

```powershell
# 1. Připojte se přes RDP
mstsc /v:PC-DITETE

# 2. V remote session (PowerShell jako Admin):
cd C:\Parential-Control

# 3. Záloha (přeskočte bod obnovy)
.\scripts\backup-system.ps1 -SkipRestorePoint

# 4. Volitelně vytvořte bod obnovy ručně
# Systém → Ochrana systému → Vytvořit

# 5. Instalace
.\scripts\install-all.ps1

# 6. Restart
Restart-Computer -Force
```

Toto je nejspolehlivější metoda pro remote instalaci.

