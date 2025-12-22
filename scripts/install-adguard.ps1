# Instalace AdGuard Home pomocí Docker
# Vyžaduje administrátorská práva a nainstalovaný Docker Desktop

param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = $PSScriptRoot
)

# Kontrola administrátorských práv
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Tento skript vyžaduje administrátorská práva!"
    exit 1
}

Write-Host "`n=== Instalace AdGuard Home ===" -ForegroundColor Cyan

# Kontrola Docker
$dockerInstalled = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerInstalled) {
    Write-Error "Docker není nainstalován! Prosím nainstalujte Docker Desktop z https://www.docker.com/products/docker-desktop"
    exit 1
}

# Kontrola, zda Docker běží
try {
    docker ps | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker není spuštěný! Prosím spusťte Docker Desktop."
        exit 1
    }
} catch {
    Write-Error "Docker není spuštěný! Prosím spusťte Docker Desktop."
    exit 1
}

# Vytvoření adresářů pro konfiguraci
$workDir = Join-Path $ProjectPath "adguard-config\work"
$confDir = Join-Path $ProjectPath "adguard-config\conf"

if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    Write-Host "Vytvořen adresář: $workDir" -ForegroundColor Green
}

if (-not (Test-Path $confDir)) {
    New-Item -ItemType Directory -Path $confDir -Force | Out-Null
    Write-Host "Vytvořen adresář: $confDir" -ForegroundColor Green
}

# Kontrola docker-compose.yml
$dockerComposeFile = Join-Path $ProjectPath "docker-compose.yml"
if (-not (Test-Path $dockerComposeFile)) {
    Write-Error "Soubor docker-compose.yml nenalezen v: $ProjectPath"
    exit 1
}

# Zastavení existujícího kontejneru
Write-Host "`nZastavování existujícího kontejneru (pokud existuje)..." -ForegroundColor Yellow
docker-compose -f $dockerComposeFile down 2>$null

# Spuštění AdGuard Home
Write-Host "`nSpouštění AdGuard Home..." -ForegroundColor Yellow
Set-Location $ProjectPath
docker-compose up -d

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nAdGuard Home byl úspěšně spuštěn!" -ForegroundColor Green
    Write-Host "`nWebové rozhraní: http://localhost:3000" -ForegroundColor Cyan
    Write-Host "DNS server: 127.0.0.1:53" -ForegroundColor Cyan
    Write-Host "`nPoznámka: Při prvním spuštění budete muset dokončit nastavení přes webové rozhraní." -ForegroundColor Yellow
    Write-Host "Poté nastavte DNS na tomto PC na 127.0.0.1" -ForegroundColor Yellow
} else {
    Write-Error "Chyba při spouštění AdGuard Home!"
    exit 1
}

