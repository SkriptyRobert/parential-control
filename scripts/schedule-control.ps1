# Časový rozvrh - Kontrola povolených časových oken
# Spouští se přes Scheduled Task každých 5 minut

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\time-limits.json"
)

# Načtení konfigurace
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $scheduleConfig = $config.schedule
} else {
    $scheduleConfig = @{
        enabled = $false
        allowedWindows = @()
        action = "shutdown"
    }
}

if (-not $scheduleConfig.enabled) {
    exit 0
}

$logFile = "$env:ProgramData\ParentalControl\schedule-control.log"
$logDir = Split-Path $logFile -Parent

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Získání aktuálního času a dne
$currentTime = Get-Date
$currentDay = $currentTime.DayOfWeek.ToString()
$currentHour = $currentTime.Hour
$currentMinute = $currentTime.Minute
$currentMinutes = $currentHour * 60 + $currentMinute

# Mapování dnů v týdnu
$dayMapping = @{
    "Monday" = "Monday"
    "Tuesday" = "Tuesday"
    "Wednesday" = "Wednesday"
    "Thursday" = "Thursday"
    "Friday" = "Friday"
    "Saturday" = "Saturday"
    "Sunday" = "Sunday"
}

# Kontrola, zda je aktuální čas v povoleném okně
$isAllowed = $false

foreach ($window in $scheduleConfig.allowedWindows) {
    if ($window.day -eq $currentDay) {
        $startParts = $window.start.Split(':')
        $endParts = $window.end.Split(':')
        $startMinutes = [int]$startParts[0] * 60 + [int]$startParts[1]
        $endMinutes = [int]$endParts[0] * 60 + [int]$endParts[1]
        
        if ($currentMinutes -ge $startMinutes -and $currentMinutes -lt $endMinutes) {
            $isAllowed = $true
            break
        }
    }
}

if (-not $isAllowed) {
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Aktuální čas ($($currentTime.ToString('HH:mm'))) není v povoleném okně pro $currentDay"
    Add-Content -Path $logFile -Value $logMessage
    
    # Kontrola, zda je někdo přihlášený
    $loggedInUsers = quser 2>$null
    if ($loggedInUsers) {
        # Najít povolené okno pro dnešní den
        $todayWindow = $scheduleConfig.allowedWindows | Where-Object { $_.day -eq $currentDay } | Select-Object -First 1
        
        if ($todayWindow) {
            $message = "Rodičovská kontrola: Aktuální čas není v povoleném okně. Povoleno je: $($todayWindow.start) - $($todayWindow.end). Počítač bude vypnut za 60 sekund."
        } else {
            $message = "Rodičovská kontrola: Dnes není povoleno používání počítače. Počítač bude vypnut za 60 sekund."
        }
        
        # Zobrazení upozornění
        $loggedInUsers | ForEach-Object {
            if ($_ -match '^(\S+)') {
                $username = $matches[1]
                if ($username -ne 'USERNAME') {
                    try {
                        msg $username "$message" 2>$null
                    } catch {
                        Add-Content -Path $logFile -Value "Nelze zobrazit zprávu uživateli $username"
                    }
                }
            }
        }
        
        Start-Sleep -Seconds 60
    }
    
    # Vypnutí nebo odhlášení
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Vypínání PC kvůli časovému rozvrhu..."
    
    if ($scheduleConfig.action -eq "shutdown") {
        Stop-Computer -Force
    } elseif ($scheduleConfig.action -eq "logoff") {
        logoff
    }
} else {
    # Logování povoleného času (jen jednou za hodinu)
    $lastLogFile = "$env:ProgramData\ParentalControl\schedule-last-log.txt"
    $shouldLog = $true
    
    if (Test-Path $lastLogFile) {
        $lastLogTime = Get-Content $lastLogFile
        $lastLog = [DateTime]::Parse($lastLogTime)
        if (((Get-Date) - $lastLog).TotalHours -lt 1) {
            $shouldLog = $false
        }
    }
    
    if ($shouldLog) {
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Aktuální čas je v povoleném okně pro $currentDay"
        Add-Content -Path $logFile -Value $logMessage
        (Get-Date).ToString() | Set-Content $lastLogFile
    }
}

