# Windows Firewall Rules - Blokování aplikací
# Vyžaduje administrátorská práva

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\apps-to-block.json",
    
    [Parameter(Mandatory=$false)]
    [switch]$Remove
)

# Kontrola administrátorských práv
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Tento skript vyžaduje administrátorská práva!"
    exit 1
}

# Načtení konfigurace
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Konfigurační soubor nenalezen: $ConfigPath"
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json

function Block-Application {
    param(
        [string]$AppName,
        [string[]]$ProcessNames,
        [string[]]$Paths
    )
    
    $ruleName = "ParentalControl-Block-$AppName"
    
    if ($Remove) {
        # Odstranění pravidla
        $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($existingRule) {
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            Write-Host "Odstraněno pravidlo: $ruleName" -ForegroundColor Yellow
        }
        return
    }
    
    # Kontrola existence pravidla
    $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existingRule) {
        Write-Host "Pravidlo již existuje: $ruleName" -ForegroundColor Yellow
        return
    }
    
    # Vytvoření pravidel pro každý proces
    foreach ($processName in $ProcessNames) {
        try {
            # Blokování odchozího provozu
            if ($config.blockAllMatching) {
                New-NetFirewallRule -DisplayName "$ruleName-Out-$processName" `
                    -Direction Outbound `
                    -Program "*\$processName" `
                    -Action Block `
                    -Profile Any `
                    -Enabled True `
                    -ErrorAction Stop | Out-Null
                
                Write-Host "Vytvořeno pravidlo pro blokování: $AppName ($processName - Outbound)" -ForegroundColor Green
            }
            
            # Blokování příchozího provozu (pokud je zapnuto)
            if ($config.blockInbound) {
                New-NetFirewallRule -DisplayName "$ruleName-In-$processName" `
                    -Direction Inbound `
                    -Program "*\$processName" `
                    -Action Block `
                    -Profile Any `
                    -Enabled True `
                    -ErrorAction Stop | Out-Null
                
                Write-Host "Vytvořeno pravidlo pro blokování: $AppName ($processName - Inbound)" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "Chyba při vytváření pravidla pro $processName : $_"
        }
    }
    
    # Vytvoření pravidel pro konkrétní cesty
    foreach ($path in $Paths) {
        # Rozbalení proměnných prostředí
        $expandedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        
        # Pokud cesta obsahuje wildcard, použijeme Get-ChildItem
        if ($expandedPath -match '\*') {
            $resolvedPaths = Get-ChildItem -Path $expandedPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            foreach ($resolvedPath in $resolvedPaths) {
                if (Test-Path $resolvedPath) {
                    try {
                        if ($config.blockOutbound) {
                            New-NetFirewallRule -DisplayName "$ruleName-Out-Path-$([System.IO.Path]::GetFileName($resolvedPath))" `
                                -Direction Outbound `
                                -Program $resolvedPath `
                                -Action Block `
                                -Profile Any `
                                -Enabled True `
                                -ErrorAction Stop | Out-Null
                        }
                        
                        if ($config.blockInbound) {
                            New-NetFirewallRule -DisplayName "$ruleName-In-Path-$([System.IO.Path]::GetFileName($resolvedPath))" `
                                -Direction Inbound `
                                -Program $resolvedPath `
                                -Action Block `
                                -Profile Any `
                                -Enabled True `
                                -ErrorAction Stop | Out-Null
                        }
                        
                        Write-Host "Vytvořeno pravidlo pro cestu: $resolvedPath" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "Chyba při vytváření pravidla pro cestu $resolvedPath : $_"
                    }
                }
            }
        }
        else {
            if (Test-Path $expandedPath) {
                try {
                    if ($config.blockOutbound) {
                        New-NetFirewallRule -DisplayName "$ruleName-Out-Path-$([System.IO.Path]::GetFileName($expandedPath))" `
                            -Direction Outbound `
                            -Program $expandedPath `
                            -Action Block `
                            -Profile Any `
                            -Enabled True `
                            -ErrorAction Stop | Out-Null
                    }
                    
                    if ($config.blockInbound) {
                        New-NetFirewallRule -DisplayName "$ruleName-In-Path-$([System.IO.Path]::GetFileName($expandedPath))" `
                            -Direction Inbound `
                            -Program $expandedPath `
                            -Action Block `
                            -Profile Any `
                            -Enabled True `
                            -ErrorAction Stop | Out-Null
                    }
                    
                    Write-Host "Vytvořeno pravidlo pro cestu: $expandedPath" -ForegroundColor Green
                }
                catch {
                    Write-Warning "Chyba při vytváření pravidla pro cestu $expandedPath : $_"
                }
            }
        }
    }
}

# Zpracování všech aplikací
Write-Host "`n=== Windows Firewall Rules - Parental Control ===" -ForegroundColor Cyan
Write-Host "Konfigurace: $ConfigPath" -ForegroundColor Cyan
Write-Host "Akce: $(if ($Remove) { 'Odstranění' } else { 'Vytváření' })`n" -ForegroundColor Cyan

foreach ($app in $config.applications) {
    Block-Application -AppName $app.name -ProcessNames $app.processNames -Paths $app.paths
}

Write-Host "`n=== Hotovo ===" -ForegroundColor Green

