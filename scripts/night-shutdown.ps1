# Noční vypínání PC - Po půlnoci a před 6:00
# Spouští se přes Scheduled Task jako SYSTEM

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\time-limits.json"
)

# Načtení konfigurace
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $nightConfig = $config.nightShutdown
} else {
    # Výchozí hodnoty
    $nightConfig = @{
        enabled = $true
        startTime = "00:00"
        endTime = "06:00"
        action = "shutdown"
    }
}

if (-not $nightConfig.enabled) {
    exit 0
}

# Získání aktuálního času
$currentTime = Get-Date
$currentHour = $currentTime.Hour
$currentMinute = $currentTime.Minute

# Parsování času z konfigurace
$startTimeParts = $nightConfig.startTime.Split(':')
$endTimeParts = $nightConfig.endTime.Split(':')
$startHour = [int]$startTimeParts[0]
$startMinute = [int]$startTimeParts[1]
$endHour = [int]$endTimeParts[0]
$endMinute = [int]$endTimeParts[1]

# Kontrola, zda jsme v nočním časovém okně
$shouldShutdown = $false

if ($startHour -lt $endHour) {
    # Normální případ: 00:00 - 06:00
    $currentMinutes = $currentHour * 60 + $currentMinute
    $startMinutes = $startHour * 60 + $startMinute
    $endMinutes = $endHour * 60 + $endMinute
    
    if ($currentMinutes -ge $startMinutes -or $currentMinutes -lt $endMinutes) {
        $shouldShutdown = $true
    }
} else {
    # Překrývající se den (např. 22:00 - 06:00)
    $currentMinutes = $currentHour * 60 + $currentMinute
    $startMinutes = $startHour * 60 + $startMinute
    $endMinutes = $endHour * 60 + $endMinute
    
    if ($currentMinutes -ge $startMinutes -or $currentMinutes -lt $endMinutes) {
        $shouldShutdown = $true
    }
}

if ($shouldShutdown) {
    $logFile = "$env:ProgramData\ParentalControl\night-shutdown.log"
    $logDir = Split-Path $logFile -Parent
    
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Noční vypínání: Aktuální čas $($currentTime.ToString('HH:mm')) je v zakázaném okně ($($nightConfig.startTime) - $($nightConfig.endTime))"
    Add-Content -Path $logFile -Value $logMessage
    
    # Kontrola, zda je někdo přihlášený
    $loggedInUsers = quser 2>$null
    if ($loggedInUsers) {
        # Vypnutí PC s upozorněním
        $message = "Rodičovská kontrola: Počítač bude vypnut z důvodu nočního zákazu používání ($($nightConfig.startTime) - $($nightConfig.endTime)). Vypnutí za 60 sekund."
        
        # Zobrazení upozornění všem přihlášeným uživatelům
        $loggedInUsers | ForEach-Object {
            if ($_ -match '^(\S+)') {
                $username = $matches[1]
                if ($username -ne 'USERNAME') {
                    try {
                        # Použití msg.exe pro zobrazení zprávy (vyžaduje správná oprávnění)
                        msg $username "$message" 2>$null
                    } catch {
                        # Fallback - logování
                        Add-Content -Path $logFile -Value "Nelze zobrazit zprávu uživateli $username"
                    }
                }
            }
        }
        
        Start-Sleep -Seconds 60
    }
    
    # Vypnutí PC
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Vypínání PC..."
    
    if ($nightConfig.action -eq "shutdown") {
        Stop-Computer -Force
    } elseif ($nightConfig.action -eq "logoff") {
        logoff
    }
}

