# Obnovení systému ze zálohy
# Vyžaduje administrátorská práva

param(
    [Parameter(Mandatory=$false)]
    [string]$BackupPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseLastBackup,
    
    [Parameter(Mandatory=$false)]
    [switch]$RestorePointOnly
)

# Kontrola administrátorských práv
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Tento skript vyžaduje administrátorská práva!"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Obnovení systému ze zálohy" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Najít poslední zálohu
if ($UseLastBackup -or -not $BackupPath) {
    $lastBackupFile = "$env:ProgramData\ParentalControl\Backups\last-backup.txt"
    if (Test-Path $lastBackupFile) {
        $BackupPath = Get-Content $lastBackupFile
        Write-Host "Používám poslední zálohu: $BackupPath" -ForegroundColor Yellow
    } else {
        Write-Error "Nebyla nalezena žádná předchozí záloha!"
        Write-Host "Spusťte skript s parametrem -BackupPath nebo nejdřív vytvořte zálohu." -ForegroundColor Yellow
        exit 1
    }
}

if (-not (Test-Path $BackupPath)) {
    Write-Error "Zálohovací adresář nenalezen: $BackupPath"
    exit 1
}

# Načtení info o záloze
$backupInfoFile = Join-Path $BackupPath "backup-info.json"
if (Test-Path $backupInfoFile) {
    $backupInfo = Get-Content $backupInfoFile | ConvertFrom-Json
    Write-Host "Informace o záloze:" -ForegroundColor Cyan
    Write-Host "  Vytvořeno: $($backupInfo.Date)" -ForegroundColor White
    Write-Host "  Počítač: $($backupInfo.ComputerName)" -ForegroundColor White
    Write-Host "  Uživatel: $($backupInfo.UserName)" -ForegroundColor White
}

Write-Host "`nVarování: Tato operace obnoví systém do stavu před instalací rodičovské kontroly." -ForegroundColor Yellow
$response = Read-Host "Pokračovat? (Y/N)"
if ($response -ne "Y" -and $response -ne "y") {
    Write-Host "Zrušeno." -ForegroundColor Yellow
    exit 0
}

# 1. Obnovení z bodu obnovy
if ($RestorePointOnly) {
    Write-Host "`n[1/1] Obnovení z bodu obnovy..." -ForegroundColor Yellow
    Write-Host "Spouštím průvodce obnovením systému..." -ForegroundColor Yellow
    Write-Host "Vyberte bod obnovy vytvořený před instalací rodičovské kontroly." -ForegroundColor Yellow
    
    Start-Process -FilePath "rstrui.exe" -Wait
    
    Write-Host "`nObnovení dokončeno. Restartujte počítač." -ForegroundColor Green
    exit 0
}

# 2. Odstranění ParentalControl komponent
Write-Host "`n[1/5] Odstraňování ParentalControl komponent..." -ForegroundColor Yellow

# Odstranění Scheduled Tasks
$parentalTasks = Get-ScheduledTask -TaskName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalTasks) {
    foreach ($task in $parentalTasks) {
        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Odstraněn task: $($task.TaskName)" -ForegroundColor Yellow
    }
}

# Odstranění Firewall pravidel
$parentalRules = Get-NetFirewallRule -DisplayName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalRules) {
    foreach ($rule in $parentalRules) {
        Remove-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
        Write-Host "  Odstraněno pravidlo: $($rule.DisplayName)" -ForegroundColor Yellow
    }
}

Write-Host "ParentalControl komponenty odstraněny" -ForegroundColor Green

# 3. Obnovení registru
Write-Host "`n[2/5] Obnovení registru..." -ForegroundColor Yellow

$registryBackupDir = Join-Path $BackupPath "Registry"
if (Test-Path $registryBackupDir) {
    $regFiles = Get-ChildItem -Path $registryBackupDir -Filter "*.reg"
    
    foreach ($regFile in $regFiles) {
        try {
            $result = Start-Process -FilePath "reg.exe" -ArgumentList "import", "`"$($regFile.FullName)`"" -Wait -NoNewWindow -PassThru
            
            if ($result.ExitCode -eq 0) {
                Write-Host "  Obnoven: $($regFile.BaseName)" -ForegroundColor Green
            } else {
                Write-Warning "  Nepodařilo se obnovit: $($regFile.BaseName)"
            }
        } catch {
            Write-Warning "  Chyba při obnovení $($regFile.BaseName): $_"
        }
    }
} else {
    Write-Warning "Registry záloha nenalezena"
}

# 4. Obnovení DNS nastavení
Write-Host "`n[3/5] Obnovení DNS nastavení..." -ForegroundColor Yellow

$dnsSettingsFile = Join-Path $BackupPath "dns-settings.json"
if (Test-Path $dnsSettingsFile) {
    $dnsSettings = Get-Content $dnsSettingsFile | ConvertFrom-Json
    
    foreach ($adapter in $dnsSettings) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $adapter.ServerAddresses
            Write-Host "  Obnoven DNS pro: $($adapter.InterfaceAlias)" -ForegroundColor Green
        } catch {
            Write-Warning "  Nepodařilo se obnovit DNS pro $($adapter.InterfaceAlias): $_"
        }
    }
} else {
    Write-Warning "DNS nastavení záloha nenalezena"
}

# 5. Informace o bodu obnovy
Write-Host "`n[4/5] Informace o bodu obnovy..." -ForegroundColor Yellow

$restorePointFile = Join-Path $BackupPath "restore-point-info.json"
if (Test-Path $restorePointFile) {
    $restoreInfo = Get-Content $restorePointFile | ConvertFrom-Json
    Write-Host "Bod obnovy: $($restoreInfo.Description)" -ForegroundColor Cyan
    Write-Host "Vytvořen: $($restoreInfo.Date)" -ForegroundColor Cyan
    
    Write-Host "`nPro úplné obnovení systému můžete použít bod obnovy Windows:" -ForegroundColor Yellow
    Write-Host "1. Otevřete: Systém → Ochrana systému → Obnovení systému" -ForegroundColor White
    Write-Host "2. Vyberte bod: $($restoreInfo.Description)" -ForegroundColor White
    Write-Host "`nNebo spusťte: rstrui.exe" -ForegroundColor Cyan
}

# 6. Zastavení Docker kontejneru
Write-Host "`n[5/5] Zastavování AdGuard Home..." -ForegroundColor Yellow

$dockerComposeFile = Join-Path (Split-Path $PSScriptRoot -Parent) "docker-compose.yml"
if (Test-Path $dockerComposeFile) {
    try {
        Set-Location (Split-Path $dockerComposeFile -Parent)
        docker-compose down 2>$null
        Write-Host "AdGuard Home zastaven" -ForegroundColor Green
    } catch {
        Write-Warning "Nepodařilo se zastavit AdGuard Home: $_"
    }
}

# Shrnutí
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Obnovení dokončeno" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Obnovené komponenty:" -ForegroundColor Yellow
Write-Host "  [✓] ParentalControl komponenty odstraněny" -ForegroundColor Green
Write-Host "  [✓] Registry obnoven" -ForegroundColor Green
Write-Host "  [✓] DNS nastavení obnoveno" -ForegroundColor Green
Write-Host "  [✓] AdGuard Home zastaven" -ForegroundColor Green

Write-Host "`nDoporučené další kroky:" -ForegroundColor Yellow
Write-Host "1. Restartujte počítač pro aplikaci všech změn" -ForegroundColor White
Write-Host "2. Zkontrolujte DNS nastavení v Síťových připojeních" -ForegroundColor White
Write-Host "3. Pokud chcete úplné obnovení, použijte bod obnovy Windows (rstrui.exe)" -ForegroundColor White

Write-Host "`nPro spuštění průvodce obnovením systému:" -ForegroundColor Cyan
Write-Host "  .\scripts\restore-system.ps1 -RestorePointOnly" -ForegroundColor White

