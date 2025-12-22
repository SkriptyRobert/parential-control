# Denní limity - Sledování času použití
# Spouští se přes Scheduled Task každých 5 minut

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\time-limits.json"
)

# Načtení konfigurace
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $dailyConfig = $config.dailyLimit
    $trackingFile = $config.trackingFile
} else {
    # Výchozí hodnoty
    $dailyConfig = @{
        enabled = $true
        hours = 2
        warningAtMinutes = 15
        action = "shutdown"
    }
    $trackingFile = "$env:ProgramData\ParentalControl\usage-tracking.json"
}

if (-not $dailyConfig.enabled) {
    exit 0
}

$logFile = "$env:ProgramData\ParentalControl\daily-limit.log"
$logDir = Split-Path $logFile -Parent

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Načtení nebo vytvoření tracking souboru
$trackingDir = Split-Path $trackingFile -Parent
if (-not (Test-Path $trackingDir)) {
    New-Item -ItemType Directory -Path $trackingDir -Force | Out-Null
}

$today = Get-Date -Format "yyyy-MM-dd"
$trackingData = @{}

if (Test-Path $trackingFile) {
    try {
        $trackingData = Get-Content $trackingFile | ConvertFrom-Json | ConvertTo-Hashtable
    } catch {
        $trackingData = @{}
    }
}

# Inicializace dnešních dat
if (-not $trackingData.ContainsKey($today)) {
    $trackingData[$today] = @{
        startTime = Get-Date
        totalMinutes = 0
        lastCheck = Get-Date
        warned = $false
    }
}

$todayData = $trackingData[$today]

# Kontrola, zda je někdo přihlášený a PC je aktivní
$loggedInUsers = quser 2>$null
$isActive = $false

if ($loggedInUsers) {
    # Kontrola aktivity (myš, klávesnice, CPU)
    $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
    
    # Pokud je někdo přihlášený a CPU je aktivní, počítáme čas
    if ($cpuUsage -gt 5) {
        $isActive = $true
    }
    
    # Kontrola idle času (pokud je PC neaktivní více než 10 minut, nepočítáme)
    $lastInput = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $idleTime = (Get-Date) - $lastInput
    
    # Pokud je PC aktivní, přičteme čas od poslední kontroly
    if ($isActive -and $idleTime.TotalMinutes -lt 10) {
        $timeSinceLastCheck = ((Get-Date) - ([DateTime]$todayData.lastCheck)).TotalMinutes
        if ($timeSinceLastCheck -gt 0 -and $timeSinceLastCheck -lt 60) {
            $todayData.totalMinutes += $timeSinceLastCheck
        }
    }
}

$todayData.lastCheck = Get-Date
$totalHours = [math]::Round($todayData.totalMinutes / 60, 2)
$remainingMinutes = ($dailyConfig.hours * 60) - $todayData.totalMinutes

# Logování
$logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Použito: $totalHours hodin ($($todayData.totalMinutes) minut), zbývá: $remainingMinutes minut"
Add-Content -Path $logFile -Value $logMessage

# Upozornění při blížícím se limitu
if ($remainingMinutes -le $dailyConfig.warningAtMinutes -and $remainingMinutes -gt 0 -and -not $todayData.warned) {
    $message = "Rodičovská kontrola: Zbývá vám $remainingMinutes minut z denního limitu ($($dailyConfig.hours) hodin)."
    
    $loggedInUsers | ForEach-Object {
        if ($_ -match '^(\S+)') {
            $username = $matches[1]
            if ($username -ne 'USERNAME') {
                try {
                    msg $username "$message" 2>$null
                } catch {
                    Add-Content -Path $logFile -Value "Nelze zobrazit upozornění uživateli $username"
                }
            }
        }
    }
    
    $todayData.warned = $true
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Upozornění zobrazeno uživateli"
}

# Kontrola překročení limitu
if ($todayData.totalMinutes -ge ($dailyConfig.hours * 60)) {
    $message = "Rodičovská kontrola: Byl dosažen denní limit ($($dailyConfig.hours) hodin). Počítač bude vypnut za 60 sekund."
    
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
    
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Dosáhnut denní limit, vypínání PC..."
    
    if ($dailyConfig.action -eq "shutdown") {
        Stop-Computer -Force
    } elseif ($dailyConfig.action -eq "logoff") {
        logoff
    }
}

# Uložení tracking dat
$trackingData[$today] = $todayData
$trackingData | ConvertTo-Json -Depth 10 | Set-Content $trackingFile

# Pomocná funkce pro konverzi PSCustomObject na Hashtable
function ConvertTo-Hashtable {
    param($Object)
    
    if ($Object -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $Object.Keys) {
            $hash[$key] = ConvertTo-Hashtable -Object $Object[$key]
        }
        return $hash
    }
    elseif ($Object -is [System.Array]) {
        return $Object | ForEach-Object { ConvertTo-Hashtable -Object $_ }
    }
    elseif ($Object -is [PSCustomObject]) {
        $hash = @{}
        $Object.PSObject.Properties | ForEach-Object {
            $hash[$_.Name] = ConvertTo-Hashtable -Object $_.Value
        }
        return $hash
    }
    else {
        return $Object
    }
}

