# Apply GPO policies via Registry
# Requires administrator privileges

param(
    [Parameter(Mandatory=$false)]
    [string]$RegistryFile = "$PSScriptRoot\..\gpo\registry-export.reg",
    
    [Parameter(Mandatory=$false)]
    [switch]$Remove
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n=== Applying GPO Policies ===" -ForegroundColor Cyan

if ($Remove) {
    Write-Host "Removing policies..." -ForegroundColor Yellow
    
    # Remove DNS settings
    Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "NameServer" -ErrorAction SilentlyContinue
    
    # Remove other keys
    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_AllowAdvancedTCPIPConfig" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_AllowNetBridge_NLA" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\NetworkConnections" -Name "NC_ShowSharedAccessUI" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableRegistryTools" -ErrorAction SilentlyContinue
    
    Write-Host "Policies removed." -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $RegistryFile)) {
    Write-Error "Registry file not found: $RegistryFile"
    exit 1
}

Write-Host "Applying policies from: $RegistryFile" -ForegroundColor Yellow
Write-Host "Warning: Some policies are for HKEY_CURRENT_USER - they apply to currently logged in user!" -ForegroundColor Yellow

$response = Read-Host "Continue? (Y/N)"
if ($response -ne "Y" -and $response -ne "y") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# Import registry file
try {
    Start-Process -FilePath "reg.exe" -ArgumentList "import", "`"$RegistryFile`"" -Wait -NoNewWindow
    Write-Host "Policies applied successfully!" -ForegroundColor Green
    Write-Host "`nWe recommend restarting PC to fully apply all changes." -ForegroundColor Yellow
} catch {
    Write-Error "Error applying policies: $_"
    exit 1
}
