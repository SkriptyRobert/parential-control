# Aplikace GPO policies přes Registry
# Vyžaduje administrátorská práva

param(
    [Parameter(Mandatory=$false)]
    [string]$RegistryFile = "$PSScriptRoot\..\gpo\registry-export.reg",
    
    [Parameter(Mandatory=$false)]
    [switch]$Remove
)

# Kontrola administrátorských práv
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Tento skript vyžaduje administrátorská práva!"
    exit 1
}

Write-Host "`n=== Aplikace GPO Policies ===" -ForegroundColor Cyan

if ($Remove) {
    Write-Host "Odstraňování policies..." -ForegroundColor Yellow
    
    # Odstranění DNS nastavení
    Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "NameServer" -ErrorAction SilentlyContinue
    
    # Odstranění dalších klíčů
    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_AllowAdvancedTCPIPConfig" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_AllowNetBridge_NLA" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_ShowSharedAccessUI" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableRegistryTools" -ErrorAction SilentlyContinue
    
    Write-Host "Policies byly odstraněny." -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $RegistryFile)) {
    Write-Error "Registry soubor nenalezen: $RegistryFile"
    exit 1
}

Write-Host "Aplikování policies z: $RegistryFile" -ForegroundColor Yellow
Write-Host "Pozor: Některé policies jsou pro HKEY_CURRENT_USER - aplikují se pro aktuálně přihlášeného uživatele!" -ForegroundColor Yellow

$response = Read-Host "Pokračovat? (Y/N)"
if ($response -ne "Y" -and $response -ne "y") {
    Write-Host "Zrušeno." -ForegroundColor Yellow
    exit 0
}

# Import registry souboru
try {
    Start-Process -FilePath "reg.exe" -ArgumentList "import", "`"$RegistryFile`"" -Wait -NoNewWindow
    Write-Host "Policies byly úspěšně aplikovány!" -ForegroundColor Green
    Write-Host "`nDoporučujeme restartovat PC pro plnou aplikaci všech změn." -ForegroundColor Yellow
} catch {
    Write-Error "Chyba při aplikaci policies: $_"
    exit 1
}

