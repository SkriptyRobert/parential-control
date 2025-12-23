# Kompletní odstranění rodičovské kontroly
# Vyžaduje administrátorská práva

param(
    [Parameter(Mandatory=$false)]
    [switch]$KeepLogs
)

# Kontrola administrátorských práv
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Tento skript vyžaduje administrátorská práva!"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Odstranění rodičovské kontroly" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Varování: Tento skript kompletně odstraní všechny komponenty rodičovské kontroly." -ForegroundColor Yellow
$response = Read-Host "Pokračovat? (Y/N)"
if ($response -ne "Y" -and $response -ne "y") {
    Write-Host "Zrušeno." -ForegroundColor Yellow
    exit 0
}

# 1. Odstranění Scheduled Tasks
Write-Host "`n[1/5] Odstraňování Scheduled Tasks..." -ForegroundColor Yellow

$parentalTasks = Get-ScheduledTask -TaskName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalTasks) {
    foreach ($task in $parentalTasks) {
        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Odstraněn: $($task.TaskName)" -ForegroundColor Green
    }
    Write-Host "Scheduled Tasks odstraněny" -ForegroundColor Green
} else {
    Write-Host "Žádné ParentalControl Scheduled Tasks nenalezeny" -ForegroundColor Gray
}

# 2. Odstranění Firewall pravidel
Write-Host "`n[2/5] Odstraňování Firewall pravidel..." -ForegroundColor Yellow

$parentalRules = Get-NetFirewallRule -DisplayName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalRules) {
    foreach ($rule in $parentalRules) {
        Remove-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
        Write-Host "  Odstraněno: $($rule.DisplayName)" -ForegroundColor Green
    }
    Write-Host "Firewall pravidla odstraněna ($(($parentalRules | Measure-Object).Count) pravidel)" -ForegroundColor Green
} else {
    Write-Host "Žádná ParentalControl Firewall pravidla nenalezena" -ForegroundColor Gray
}

# 3. Zastavení a odstranění AdGuard Home
Write-Host "`n[3/5] Zastavování AdGuard Home..." -ForegroundColor Yellow

$projectPath = Split-Path $PSScriptRoot -Parent
$dockerComposeFile = Join-Path $projectPath "docker-compose.yml"

if (Test-Path $dockerComposeFile) {
    try {
        Set-Location $projectPath
        
        # Zastavení kontejneru
        docker-compose down
        
        Write-Host "AdGuard Home zastaven a odstraněn" -ForegroundColor Green
        
        # Volitelné: Odstranění dat
        Write-Host "`nChcete odstranit také AdGuard Home data (konfigurace, logy)? (Y/N)" -ForegroundColor Yellow
        $removeData = Read-Host
        
        if ($removeData -eq "Y" -or $removeData -eq "y") {
            $adguardDataDir = Join-Path $projectPath "adguard-config"
            if (Test-Path $adguardDataDir) {
                Remove-Item -Path $adguardDataDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "AdGuard Home data odstraněna" -ForegroundColor Green
            }
        }
    } catch {
        Write-Warning "Nepodařilo se zastavit AdGuard Home: $_"
    }
} else {
    Write-Host "Docker Compose soubor nenalezen" -ForegroundColor Gray
}

# 4. Odstranění GPO policies (volitelné)
Write-Host "`n[4/5] Odstranění GPO policies..." -ForegroundColor Yellow

Write-Host "Chcete odstranit také GPO policies? (Y/N)" -ForegroundColor Yellow
$removeGPO = Read-Host

if ($removeGPO -eq "Y" -or $removeGPO -eq "y") {
    try {
        # Odstranění DNS nastavení
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "NameServer" -ErrorAction SilentlyContinue
        
        # Odstranění dalších klíčů
        Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_AllowAdvancedTCPIPConfig" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_AllowNetBridge_NLA" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_ShowSharedAccessUI" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableRegistryTools" -ErrorAction SilentlyContinue
        
        Write-Host "GPO policies odstraněny" -ForegroundColor Green
    } catch {
        Write-Warning "Některé GPO policies se nepodařilo odstranit: $_"
    }
} else {
    Write-Host "GPO policies ponechány" -ForegroundColor Gray
}

# 5. Odstranění logů a dat (volitelné)
Write-Host "`n[5/5] Čištění logů a dat..." -ForegroundColor Yellow

$dataDir = "$env:ProgramData\ParentalControl"

if (Test-Path $dataDir) {
    if ($KeepLogs) {
        Write-Host "Logy ponechány v: $dataDir" -ForegroundColor Yellow
    } else {
        Write-Host "Chcete odstranit také logy a tracking data? (Y/N)" -ForegroundColor Yellow
        $removeLogs = Read-Host
        
        if ($removeLogs -eq "Y" -or $removeLogs -eq "y") {
            # Ponechat backupy, odstranit jen logy
            $logsToRemove = @(
                "$dataDir\night-shutdown.log",
                "$dataDir\daily-limit.log",
                "$dataDir\schedule-control.log",
                "$dataDir\usage-tracking.json",
                "$dataDir\schedule-last-log.txt"
            )
            
            foreach ($log in $logsToRemove) {
                if (Test-Path $log) {
                    Remove-Item -Path $log -Force -ErrorAction SilentlyContinue
                    Write-Host "  Odstraněn: $log" -ForegroundColor Green
                }
            }
            
            Write-Host "Logy odstraněny (backupy ponechány)" -ForegroundColor Green
        } else {
            Write-Host "Logy ponechány" -ForegroundColor Gray
        }
    }
}

# Shrnutí
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Odstranění dokončeno" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Odstraněné komponenty:" -ForegroundColor Yellow
Write-Host "  [✓] Scheduled Tasks" -ForegroundColor Green
Write-Host "  [✓] Firewall pravidla" -ForegroundColor Green
Write-Host "  [✓] AdGuard Home" -ForegroundColor Green

if ($removeGPO -eq "Y" -or $removeGPO -eq "y") {
    Write-Host "  [✓] GPO policies" -ForegroundColor Green
}

Write-Host "`nDoporučené další kroky:" -ForegroundColor Yellow
Write-Host "1. Restartujte počítač" -ForegroundColor White
Write-Host "2. Zkontrolujte DNS nastavení a nastavte je na automatické" -ForegroundColor White
Write-Host "3. Ověřte, že aplikace fungují normálně" -ForegroundColor White

Write-Host "`nPoznámka: Backupy jsou ponechány v: $env:ProgramData\ParentalControl\Backups" -ForegroundColor Cyan
Write-Host "Pro obnovení systému z bodu obnovy spusťte: rstrui.exe" -ForegroundColor Cyan

