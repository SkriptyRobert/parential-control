# Záloha systému před aplikací rodičovské kontroly
# Vyžaduje administrátorská práva

param(
    [Parameter(Mandatory=$false)]
    [string]$BackupPath = "$env:ProgramData\ParentalControl\Backups"
)

# Kontrola administrátorských práv
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Tento skript vyžaduje administrátorská práva!"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Záloha systému - Rodičovská kontrola" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupDir = Join-Path $BackupPath $timestamp

# Vytvoření adresáře pro zálohu
if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
}

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Write-Host "Adresář pro zálohu: $backupDir" -ForegroundColor Green

# 1. Vytvoření bodu obnovy (System Restore Point)
Write-Host "`n[1/5] Vytváření bodu obnovy..." -ForegroundColor Yellow

try {
    # Povolení System Protection (pokud není zapnuté)
    $systemDrive = $env:SystemDrive
    
    # Kontrola, zda je System Protection zapnutý
    $systemProtection = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    
    if (-not $systemProtection) {
        Write-Host "System Protection není zapnutý. Pokouším se zapnout..." -ForegroundColor Yellow
        Enable-ComputerRestore -Drive "$systemDrive\" -ErrorAction SilentlyContinue
    }
    
    # Vytvoření bodu obnovy
    $restorePointDescription = "Parental Control - Před instalací - $timestamp"
    Checkpoint-Computer -Description $restorePointDescription -RestorePointType "MODIFY_SETTINGS"
    
    Write-Host "Bod obnovy vytvořen: $restorePointDescription" -ForegroundColor Green
    
    # Uložení informace o bodu obnovy
    $restoreInfo = @{
        Description = $restorePointDescription
        Timestamp = $timestamp
        Date = Get-Date
    }
    $restoreInfo | ConvertTo-Json | Set-Content "$backupDir\restore-point-info.json"
    
} catch {
    Write-Warning "Nepodařilo se vytvořit bod obnovy: $_"
    Write-Host "Pokračuji se zálohou registry a firewall pravidel..." -ForegroundColor Yellow
}

# 2. Záloha celého registru (důležité klíče)
Write-Host "`n[2/5] Zálohování registru..." -ForegroundColor Yellow

$registryBackupDir = Join-Path $backupDir "Registry"
New-Item -ItemType Directory -Path $registryBackupDir -Force | Out-Null

# Důležité klíče pro zálohování
$registryKeys = @(
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; Name = "TCP-IP-Parameters"},
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy"; Name = "FirewallPolicy"},
    @{Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows"; Name = "Windows-Policies"},
    @{Path = "HKCU:\Software\Policies\Microsoft\Windows"; Name = "User-Windows-Policies"},
    @{Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies"; Name = "User-Policies"}
)

foreach ($key in $registryKeys) {
    $regFile = Join-Path $registryBackupDir "$($key.Name).reg"
    
    # Převod HKLM: na HKEY_LOCAL_MACHINE pro reg.exe
    $regPath = $key.Path -replace "HKLM:", "HKEY_LOCAL_MACHINE" -replace "HKCU:", "HKEY_CURRENT_USER"
    
    try {
        # Export registry klíče
        $result = Start-Process -FilePath "reg.exe" -ArgumentList "export", "`"$regPath`"", "`"$regFile`"", "/y" -Wait -NoNewWindow -PassThru
        
        if ($result.ExitCode -eq 0) {
            Write-Host "  Zálohován: $($key.Name)" -ForegroundColor Green
        } else {
            Write-Warning "  Nepodařilo se zálohovat: $($key.Name) (možná klíč neexistuje)"
        }
    } catch {
        Write-Warning "  Chyba při zálohování $($key.Name): $_"
    }
}

# 3. Záloha aktuálních DNS nastavení
Write-Host "`n[3/5] Zálohování DNS nastavení..." -ForegroundColor Yellow

$dnsSettings = Get-DnsClientServerAddress | Where-Object {$_.ServerAddresses.Count -gt 0} | Select-Object InterfaceAlias, InterfaceIndex, ServerAddresses
$dnsSettings | ConvertTo-Json -Depth 10 | Set-Content "$backupDir\dns-settings.json"
Write-Host "DNS nastavení zálohováno" -ForegroundColor Green

# 4. Záloha současných Firewall pravidel
Write-Host "`n[4/5] Zálohování Firewall pravidel..." -ForegroundColor Yellow

# Export všech firewall pravidel
$firewallRules = Get-NetFirewallRule | Select-Object DisplayName, Description, Direction, Action, Enabled, Profile
$firewallRules | Export-Csv -Path "$backupDir\firewall-rules.csv" -NoTypeInformation -Encoding UTF8

# Export specifických ParentalControl pravidel (pokud existují)
$parentalRules = Get-NetFirewallRule -DisplayName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalRules) {
    $parentalRules | Export-Csv -Path "$backupDir\parental-firewall-rules.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "  Zálohováno $(($parentalRules | Measure-Object).Count) ParentalControl firewall pravidel" -ForegroundColor Yellow
}

Write-Host "Firewall pravidla zálohována" -ForegroundColor Green

# 5. Záloha současných Scheduled Tasks
Write-Host "`n[5/5] Zálohování Scheduled Tasks..." -ForegroundColor Yellow

$scheduledTasks = Get-ScheduledTask | Select-Object TaskName, TaskPath, State, Author
$scheduledTasks | Export-Csv -Path "$backupDir\scheduled-tasks.csv" -NoTypeInformation -Encoding UTF8

# Export specifických ParentalControl tasků (pokud existují)
$parentalTasks = Get-ScheduledTask -TaskName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($parentalTasks) {
    foreach ($task in $parentalTasks) {
        $taskXml = Export-ScheduledTask -TaskName $task.TaskName
        $taskXml | Set-Content "$backupDir\task-$($task.TaskName).xml"
    }
    Write-Host "  Zálohováno $(($parentalTasks | Measure-Object).Count) ParentalControl scheduled tasks" -ForegroundColor Yellow
}

Write-Host "Scheduled Tasks zálohováno" -ForegroundColor Green

# Vytvoření info souboru
Write-Host "`nVytváření info souboru..." -ForegroundColor Yellow

$backupInfo = @{
    Timestamp = $timestamp
    Date = Get-Date
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    WindowsVersion = (Get-ComputerInfo).WindowsVersion
    BackupPath = $backupDir
    Components = @{
        RestorePoint = $true
        Registry = $true
        DNS = $true
        Firewall = $true
        ScheduledTasks = $true
    }
}

$backupInfo | ConvertTo-Json -Depth 10 | Set-Content "$backupDir\backup-info.json"

# Shrnutí
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Záloha dokončena" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Umístění zálohy: $backupDir" -ForegroundColor Green
Write-Host "`nZálohované komponenty:" -ForegroundColor Yellow
Write-Host "  [✓] Bod obnovy Windows" -ForegroundColor Green
Write-Host "  [✓] Registry klíče" -ForegroundColor Green
Write-Host "  [✓] DNS nastavení" -ForegroundColor Green
Write-Host "  [✓] Firewall pravidla" -ForegroundColor Green
Write-Host "  [✓] Scheduled Tasks" -ForegroundColor Green

Write-Host "`nPro obnovení ze zálohy spusťte:" -ForegroundColor Cyan
Write-Host "  .\scripts\restore-system.ps1 -BackupPath `"$backupDir`"" -ForegroundColor White

# Uložení posledního zálohovacího adresáře
$backupDir | Set-Content "$BackupPath\last-backup.txt"

Write-Host "`nNyní můžete bezpečně pokračovat s instalací rodičovské kontroly." -ForegroundColor Green

