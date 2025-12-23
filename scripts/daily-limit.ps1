# Daily Limits - Usage Time Tracking
# Runs via Scheduled Task every 5 minutes

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\time-limits.json"
)

# Helper function to convert PSCustomObject to Hashtable
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

# Load configuration
$excludedUsers = @("rdpuser", "Administrator", "SYSTEM")
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $dailyConfig = $config.dailyLimit
    $trackingFile = $config.trackingFile
    if ($config.excludedUsers) {
        $excludedUsers = $config.excludedUsers
    }
} else {
    # Default values
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

# Check if only excluded users are logged in
$loggedInUsers = quser 2>$null
$activeNonExcludedUsers = @()

if ($loggedInUsers) {
    foreach ($line in $loggedInUsers) {
        if ($line -match '^\s*(\S+)') {
            $username = $matches[1]
            if ($username -ne 'USERNAME' -and $username -notin $excludedUsers) {
                $activeNonExcludedUsers += $username
            }
        }
    }
}

# If only excluded users are logged in, skip tracking and limits
if ($activeNonExcludedUsers.Count -eq 0) {
    exit 0
}

$logFile = "$env:ProgramData\ParentalControl\daily-limit.log"
$logDir = Split-Path $logFile -Parent

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Load or create tracking file
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

# Initialize today's data
if (-not $trackingData.ContainsKey($today)) {
    $trackingData[$today] = @{
        startTime = Get-Date
        totalMinutes = 0
        lastCheck = Get-Date
        warned = $false
    }
}

$todayData = $trackingData[$today]

# Check if someone is logged in and PC is active
$loggedInUsers = quser 2>$null
$isActive = $false

if ($loggedInUsers) {
    # Check activity (mouse, keyboard, CPU)
    $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
    
    # If someone is logged in and CPU is active, count time
    if ($cpuUsage -gt 5) {
        $isActive = $true
    }
    
    # Check idle time (if PC is inactive for more than 10 minutes, don't count)
    $lastInput = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $idleTime = (Get-Date) - $lastInput
    
    # If PC is active, add time since last check
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

# Logging
$logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Used: $totalHours hours ($($todayData.totalMinutes) min), remaining: $remainingMinutes min"
Add-Content -Path $logFile -Value $logMessage -Encoding UTF8

# Warning when approaching limit
if ($remainingMinutes -le $dailyConfig.warningAtMinutes -and $remainingMinutes -gt 0 -and -not $todayData.warned) {
    $message = "Parental Control: You have $remainingMinutes minutes remaining from daily limit ($($dailyConfig.hours) hours)."
    
    $loggedInUsers | ForEach-Object {
        if ($_ -match '^(\S+)') {
            $username = $matches[1]
            if ($username -ne 'USERNAME') {
                try {
                    msg $username "$message" 2>$null
                } catch {
                    Add-Content -Path $logFile -Value "Cannot display warning to user $username" -Encoding UTF8
                }
            }
        }
    }
    
    $todayData.warned = $true
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Warning displayed to user" -Encoding UTF8
}

# Check limit exceeded
if ($todayData.totalMinutes -ge ($dailyConfig.hours * 60)) {
    $message = "Parental Control: Daily limit reached ($($dailyConfig.hours) hours). Computer will shut down in 60 seconds."
    
    $loggedInUsers | ForEach-Object {
        if ($_ -match '^(\S+)') {
            $username = $matches[1]
            if ($username -ne 'USERNAME') {
                try {
                    msg $username "$message" 2>$null
                } catch {
                    Add-Content -Path $logFile -Value "Cannot display message to user $username" -Encoding UTF8
                }
            }
        }
    }
    
    Start-Sleep -Seconds 60
    
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Daily limit reached, shutting down PC..." -Encoding UTF8
    
    if ($dailyConfig.action -eq "shutdown") {
        Stop-Computer -Force
    } elseif ($dailyConfig.action -eq "logoff") {
        logoff
    }
}

# Save tracking data
$trackingData[$today] = $todayData
$trackingData | ConvertTo-Json -Depth 10 | Set-Content $trackingFile -Encoding UTF8
