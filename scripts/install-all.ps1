# Hlavní instalační skript - Instalace všech komponent rodičovské kontroly
# Vyžaduje administrátorská práva

param(
    [Parameter(Mandatory=$false)]
    [switch]$SkipAdGuard,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipFirewall,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipGPO,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipScheduledTasks
)

# Kontrola administrátorských práv
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Tento skript vyžaduje administrátorská práva!"
    Write-Host "Spusťte PowerShell jako administrátor a znovu spusťte tento skript." -ForegroundColor Yellow
    exit 1
}

$ScriptsPath = $PSScriptRoot
$ProjectPath = Split-Path $ScriptsPath -Parent

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Instalace rodičovské kontroly" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Doporučení zálohy
Write-Host "Doporučení: Před instalací vytvořte zálohu systému!" -ForegroundColor Yellow
Write-Host "Spusťte: .\scripts\backup-system.ps1`n" -ForegroundColor Cyan

$createBackup = Read-Host "Chcete vytvořit zálohu nyní? (Y/N)"
if ($createBackup -eq "Y" -or $createBackup -eq "y") {
    $backupScript = Join-Path $ScriptsPath "backup-system.ps1"
    if (Test-Path $backupScript) {
        & $backupScript
        Write-Host "`nZáloha dokončena. Pokračuji s instalací...`n" -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
}

# Vytvoření adresářů
$dataDir = "$env:ProgramData\ParentalControl"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    Write-Host "Vytvořen adresář pro data: $dataDir" -ForegroundColor Green
}

# 1. AdGuard Home
if (-not $SkipAdGuard) {
    Write-Host "`n[1/4] Instalace AdGuard Home..." -ForegroundColor Yellow
    $adguardScript = Join-Path $ScriptsPath "install-adguard.ps1"
    if (Test-Path $adguardScript) {
        & $adguardScript -ProjectPath $ProjectPath
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "AdGuard Home instalace selhala, ale pokračujeme..."
        }
    } else {
        Write-Warning "AdGuard Home instalační skript nenalezen: $adguardScript"
    }
} else {
    Write-Host "`n[1/4] Přeskočeno: AdGuard Home" -ForegroundColor Gray
}

# 2. Windows Firewall Rules
if (-not $SkipFirewall) {
    Write-Host "`n[2/4] Nastavení Windows Firewall pravidel..." -ForegroundColor Yellow
    $firewallScript = Join-Path $ScriptsPath "firewall-rules.ps1"
    if (Test-Path $firewallScript) {
        & $firewallScript
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Firewall pravidla byla úspěšně vytvořena." -ForegroundColor Green
        } else {
            Write-Warning "Některá firewall pravidla se nepodařilo vytvořit."
        }
    } else {
        Write-Warning "Firewall skript nenalezen: $firewallScript"
    }
} else {
    Write-Host "`n[2/4] Přeskočeno: Windows Firewall" -ForegroundColor Gray
}

# 3. GPO Policies
if (-not $SkipGPO) {
    Write-Host "`n[3/4] Aplikace GPO policies..." -ForegroundColor Yellow
    Write-Host "Pozor: GPO policies budou aplikovány. Chcete pokračovat? (Y/N)" -ForegroundColor Yellow
    $response = Read-Host
    if ($response -eq "Y" -or $response -eq "y") {
        $gpoScript = Join-Path $ScriptsPath "apply-gpo-policies.ps1"
        if (Test-Path $gpoScript) {
            & $gpoScript
        } else {
            Write-Warning "GPO skript nenalezen: $gpoScript"
        }
    } else {
        Write-Host "GPO policies přeskočeny. Můžete je aplikovat později ručně." -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[3/4] Přeskočeno: GPO Policies" -ForegroundColor Gray
}

# 4. Scheduled Tasks
if (-not $SkipScheduledTasks) {
    Write-Host "`n[4/4] Nastavení Scheduled Tasks..." -ForegroundColor Yellow
    $tasksScript = Join-Path $ScriptsPath "setup-scheduled-tasks.ps1"
    if (Test-Path $tasksScript) {
        & $tasksScript -ScriptsPath $ScriptsPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Scheduled Tasks byly úspěšně nastaveny." -ForegroundColor Green
        } else {
            Write-Warning "Některé Scheduled Tasks se nepodařilo vytvořit."
        }
    } else {
        Write-Warning "Scheduled Tasks skript nenalezen: $tasksScript"
    }
} else {
    Write-Host "`n[4/4] Přeskočeno: Scheduled Tasks" -ForegroundColor Gray
}

# Shrnutí
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Instalace dokončena" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Další kroky:" -ForegroundColor Yellow
Write-Host "1. Pokud jste nainstalovali AdGuard Home, dokončete nastavení na http://localhost:3000" -ForegroundColor White
Write-Host "2. Nastavte DNS na tomto PC na 127.0.0.1" -ForegroundColor White
Write-Host "3. Upravte časové limity v config\time-limits.json podle potřeby" -ForegroundColor White
Write-Host "4. Upravte seznam aplikací k blokování v config\apps-to-block.json" -ForegroundColor White
Write-Host "5. Pro Android telefony použijte návod v android-setup.md" -ForegroundColor White

Write-Host "`nPro kontrolu Scheduled Tasks spusťte:" -ForegroundColor Cyan
Write-Host "  Get-ScheduledTask -TaskName 'ParentalControl-*'" -ForegroundColor White

Write-Host "`nPro kontrolu Firewall pravidel spusťte:" -ForegroundColor Cyan
Write-Host "  Get-NetFirewallRule -DisplayName 'ParentalControl-*'" -ForegroundColor White

