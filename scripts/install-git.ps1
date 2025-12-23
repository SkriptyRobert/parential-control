# Install Git for Windows (64-bit)
# Git for Windows License: GPLv2 (see https://gitforwindows.org/)
# Requires administrator privileges to install to Program Files
# Run on target PC if Git is not installed

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TempDir = "$env:TEMP",

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

# If Git exists and Force is not requested, exit
$existingGit = Get-Command git.exe -ErrorAction SilentlyContinue
if ($existingGit -and -not $Force) {
    $ver = git --version
    Write-Host "Git is already installed: $ver" -ForegroundColor Green
    Write-Host "If you want to reinstall, run with -Force parameter." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n=== Installing Git for Windows (64-bit) ===" -ForegroundColor Cyan

# Ensure TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$apiUrl = "https://api.github.com/repos/git-for-windows/git/releases/latest"
Write-Host "Downloading release metadata: $apiUrl" -ForegroundColor Yellow

try {
    $release = Invoke-RestMethod -Method Get -Uri $apiUrl -ErrorAction Stop
} catch {
    Write-Error "Cannot get release metadata from GitHub: $_"
    exit 1
}

$asset = $release.assets | Where-Object { $_.name -like "*64-bit.exe" } | Select-Object -First 1

if (-not $asset) {
    Write-Error "64-bit installer not found in latest release."
    exit 1
}

if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

$installer = Join-Path $TempDir $asset.name
$installerLog = "$installer.log"

Write-Host "Downloading: $($asset.browser_download_url)" -ForegroundColor Yellow
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installer -UseBasicParsing

if (-not (Test-Path $installer)) {
    Write-Error "Failed to download installer."
    exit 1
}

Write-Host "Running silent installation..." -ForegroundColor Yellow
$installArgs = @(
    "/VERYSILENT",
    "/NOCANCEL",
    "/NORESTART",
    "/SUPPRESSMSGBOXES",
    "/CLOSEAPPLICATIONS",
    "/RESTARTAPPLICATIONS",
    "/LOG=""$installerLog"""
)

$proc = Start-Process -FilePath $installer -ArgumentList $installArgs -Wait -PassThru

if ($proc.ExitCode -ne 0) {
    Write-Error "Installer returned error (ExitCode=$($proc.ExitCode)). Log: $installerLog"
    exit 1
}

# Verify installation
$gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Warning "Git not found in PATH after installation. Try logging out/in or restarting."
} else {
    $ver = git --version
    Write-Host "Git installed successfully: $ver" -ForegroundColor Green
}

Write-Host "Done. Installer: $installer" -ForegroundColor Cyan
