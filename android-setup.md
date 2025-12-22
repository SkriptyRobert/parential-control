# Nastavení DNS pro Android telefony

Tento dokument popisuje, jak nastavit DNS pro Android telefony, aby používaly AdGuard Home instance z PC.

## Předpoklady

- AdGuard Home běží na PC dítěte
- PC a telefon jsou ve stejné síti (Wi-Fi)
- Znáte lokální IP adresu PC (např. 192.168.1.100)

## Metoda 1: Manuální nastavení DNS na telefonu (Doporučeno)

### Krok 1: Zjistěte IP adresu PC

Na PC s AdGuard Home spusťte v PowerShell:

```powershell
ipconfig | findstr IPv4
```

Poznamenejte si IP adresu (např. `192.168.1.100`).

### Krok 2: Nastavení DNS na Android telefonu

1. Otevřete **Nastavení** na telefonu
2. Přejděte na **Síť a internet** → **Wi‑Fi**
3. Dlouze stiskněte na připojenou Wi‑Fi síť
4. Vyberte **Upravit** nebo **Správa nastavení sítě**
5. Rozbalte **Pokročilé možnosti**
6. V sekci **IP nastavení** změňte z "DHCP" na **"Statické"** nebo **"Ruční"**
7. Vyplňte:
   - **IP adresa**: Použijte aktuální IP telefonu (nebo podobnou, např. 192.168.1.101)
   - **Brána**: IP adresa routeru (obvykle 192.168.1.1 nebo 192.168.0.1)
   - **Délka síťové předpony**: 24 (nebo 255.255.255.0)
   - **DNS 1**: **IP adresa PC s AdGuard Home** (např. 192.168.1.100)
   - **DNS 2**: 8.8.8.8 (záložní DNS)
8. Uložte nastavení

### Krok 3: Ověření

1. Otevřete prohlížeč na telefonu
2. Zkuste navštívit nějakou stránku
3. V AdGuard Home na PC zkontrolujte logy - měli byste vidět DNS dotazy z telefonu

## Metoda 2: Router DHCP (Pokud router umožní)

Pokud váš Vodafone router umožňuje změnu DNS serverů v DHCP nastavení:

1. Přihlaste se do routeru (obvykle http://192.168.1.1 nebo http://192.168.0.1)
2. Najděte sekci **DHCP** nebo **Síťové nastavení**
3. Změňte **DNS servery** na IP adresu PC s AdGuard Home
4. Uložte a restartujte router

**Poznámka**: Většina základních routerů (včetně Vodafone) tuto možnost nemá. V takovém případě použijte Metodu 1.

## Metoda 3: AdGuard DNS (Alternativa)

Pokud nemůžete použít lokální AdGuard Home instance:

1. Na telefonu použijte veřejné AdGuard DNS:
   - **DNS 1**: 94.140.14.14
   - **DNS 2**: 94.140.15.15

2. Nebo použijte AdGuard aplikaci pro Android (vyžaduje root nebo VPN)

## Řešení problémů

### Telefon se nemůže připojit k internetu

- Zkontrolujte, že PC s AdGuard Home je zapnuté a běží
- Ověřte, že AdGuard Home naslouchá na portu 53
- Zkontrolujte firewall na PC - port 53 musí být otevřený

### DNS dotazy nejsou vidět v AdGuard Home

- Ověřte, že používáte správnou IP adresu PC
- Zkontrolujte, že telefon a PC jsou ve stejné síti
- Restartujte Wi‑Fi připojení na telefonu

### Telefon stále používá starý DNS

- Vymažte cache DNS na telefonu (obvykle restart telefonu)
- Zkontrolujte, že jste správně nastavili statickou IP s DNS

## Bezpečnostní poznámky

- **Důležité**: Pokud PC s AdGuard Home není zapnuté, telefon nebude mít DNS a nebude moci přistupovat k internetu
- Pro každé dítě PC můžete nastavit telefon na IP adresu příslušného PC
- Pokud chcete centrální řešení, budete potřebovat jeden PC, který běží nonstop (což není váš případ)

## Doporučení

Pro vaši situaci (žádný nonstop běžící PC) doporučujeme:

1. **Pro každé dítě**: Nastavte jeho telefon na DNS jeho PC
2. **Když PC není zapnuté**: Telefon nebude mít internet (což může být i výhoda pro rodičovskou kontrolu)
3. **Alternativa**: Použijte veřejné AdGuard DNS (94.140.14.14) jako záložní, ale pak nebudete mít lokální kontrolu

## Testování

Po nastavení DNS:

1. Otevřete prohlížeč na telefonu
2. Zkuste navštívit blokovanou stránku (např. pornografii)
3. Měla by být zablokována AdGuard Home
4. V AdGuard Home logu uvidíte pokusy o přístup

