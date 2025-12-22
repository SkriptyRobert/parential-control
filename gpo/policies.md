# GPO Policies - Rodičovská kontrola

Tento dokument popisuje Group Policy Object (GPO) nastavení pro rodičovskou kontrolu.

## Důležité upozornění

- Tyto policies jsou navrženy pro **standardní uživatele** (děti)
- **Administrátor** by měl mít tyto policies vypnuté nebo vyloučené
- Některé policies mohou být příliš restriktivní - upravte podle potřeby

## Aplikace policies

### Metoda 1: Ruční aplikace přes Registry Editor

1. Otevřete Registry Editor jako administrátor (`regedit`)
2. Otevřete soubor `registry-export.reg`
3. Potvrďte import
4. **Pozor**: Některé klíče jsou pro HKEY_CURRENT_USER - aplikujte je pro každého uživatele

### Metoda 2: Group Policy Editor (gpedit.msc)

1. Otevřete `gpedit.msc` jako administrátor
2. Přejděte na: `Computer Configuration` → `Administrative Templates` → `Network` → `Network Connections`
3. Povolte: "Prohibit access to properties of components of a LAN connection"
4. Povolte: "Prohibit changing properties of a private network"

### Metoda 3: PowerShell skript

```powershell
# Spustit jako administrátor
. .\gpo\apply-policies.ps1
```

## Doporučené GPO Policies

### 1. Blokování změny DNS

**Cesta**: `Computer Configuration` → `Administrative Templates` → `Network` → `DNS Client`

- **Zakázat změnu DNS**: Povoleno
- **DNS Suffix Search List**: Nastavit na prázdné

**Registry klíč**:
```
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters
NameServer = "127.0.0.1"
```

### 2. Blokování instalace aplikací

**Cesta**: `Computer Configuration` → `Administrative Templates` → `Windows Components` → `Windows Installer`

- **Zakázat Windows Installer**: Povoleno (pro standardní uživatele)

### 3. Blokování změny času

**Cesta**: `Computer Configuration` → `Administrative Templates` → `System` → `Windows Time Service`

- **Zakázat změnu času**: Povoleno

### 4. Firewall nastavení

**Cesta**: `Computer Configuration` → `Administrative Templates` → `Network` → `Network Connections` → `Windows Firewall`

- **Zakázat změnu firewall nastavení**: Povoleno
- **Firewall: Zapnout**: Povoleno

### 5. Zablokování příkazového řádku (volitelné)

**Cesta**: `User Configuration` → `Administrative Templates` → `System`

- **Zakázat příkazový řádek**: Povoleno
- **Zakázat PowerShell**: Povoleno (může být příliš restriktivní)

**Poznámka**: Pokud zakážete PowerShell, nebudou fungovat naše kontrolní skripty! Toto nastavení použijte pouze pokud chcete úplně zablokovat přístup k PowerShell.

### 6. Zablokování přístupu k registru

**Cesta**: `User Configuration` → `Administrative Templates` → `System`

- **Zakázat Registry Editor**: Povoleno

### 7. Zablokování změny UAC

**Cesta**: `Computer Configuration` → `Windows Settings` → `Security Settings` → `Local Policies` → `Security Options`

- **User Account Control**: Nastavit na "Always notify"

## Aplikace pro konkrétní uživatele

Pokud chcete aplikovat policies pouze pro děti (ne pro administrátora):

1. Vytvořte novou skupinu uživatelů (např. "Children")
2. Přidejte děti do této skupiny
3. Vytvořte GPO a aplikujte ho pouze na tuto skupinu
4. Vylučte administrátorskou skupinu z aplikace GPO

## Testování

Po aplikaci policies:

1. Přihlaste se jako standardní uživatel (dítě)
2. Zkuste změnit DNS nastavení - mělo by to být zablokované
3. Zkuste změnit čas - mělo by to být zablokované
4. Zkuste otevřít Registry Editor - mělo by to být zablokované

## Odstranění policies

Pro odstranění policies:

1. Otevřete `gpedit.msc`
2. Najděte aplikované policies
3. Nastavte je na "Not Configured"
4. Nebo použijte `registry-export.reg` a ručně odstraňte klíče

## Bezpečnostní poznámky

- **Nikdy neaplikujte tyto policies na administrátorský účet!**
- Před aplikací si vytvořte zálohu registru
- Testujte na testovacím PC před nasazením na produkční PC dětí
- Některé policies mohou ovlivnit funkčnost systému - upravte podle potřeby

