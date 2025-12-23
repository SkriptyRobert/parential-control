# Schedule Control - Check allowed time windows
# Runs via Scheduled Task every 5 minutes

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\time-limits.json"
)

# Load configuration
$excludedUsers = @("rdpuser", "Administrator", "SYSTEM")
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $scheduleConfig = $config.schedule
    if ($config.excludedUsers) {
        $excludedUsers = $config.excludedUsers
    }
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

# Check if only excluded users are logged in
$loggedInUsersCheck = quser 2>$null
$activeNonExcludedUsers = @()

if ($loggedInUsersCheck) {
    foreach ($line in $loggedInUsersCheck) {
        if ($line -match '^\s*(\S+)') {
            $username = $matches[1]
            if ($username -ne 'USERNAME' -and $username -notin $excludedUsers) {
                $activeNonExcludedUsers += $username
            }
        }
    }
}

# If only excluded users are logged in, skip schedule control
if ($activeNonExcludedUsers.Count -eq 0) {
    exit 0
}

$logFile = "$env:ProgramData\ParentalControl\schedule-control.log"
$logDir = Split-Path $logFile -Parent

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Get current time and day
$currentTime = Get-Date
$currentDay = $currentTime.DayOfWeek.ToString()
$currentHour = $currentTime.Hour
$currentMinute = $currentTime.Minute
$currentMinutes = $currentHour * 60 + $currentMinute

# Day mapping
$dayMapping = @{
    "Monday" = "Monday"
    "Tuesday" = "Tuesday"
    "Wednesday" = "Wednesday"
    "Thursday" = "Thursday"
    "Friday" = "Friday"
    "Saturday" = "Saturday"
    "Sunday" = "Sunday"
}

# Check if current time is in allowed window
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
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Current time ($($currentTime.ToString('HH:mm'))) is not in allowed window for $currentDay"
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
    
    # Check if someone is logged in
    $loggedInUsers = quser 2>$null
    if ($loggedInUsers) {
        # Find allowed window for today
        $todayWindow = $scheduleConfig.allowedWindows | Where-Object { $_.day -eq $currentDay } | Select-Object -First 1
        
        if ($todayWindow) {
            $message = "Parental Control: Current time is not in allowed window. Allowed: $($todayWindow.start) - $($todayWindow.end). Computer will shut down in 60 seconds."
        } else {
            $message = "Parental Control: Computer usage is not allowed today. Computer will shut down in 60 seconds."
        }
        
        # Display warning
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
    }
    
    # Shutdown or logoff
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Shutting down PC due to schedule..." -Encoding UTF8
    
    if ($scheduleConfig.action -eq "shutdown") {
        Stop-Computer -Force
    } elseif ($scheduleConfig.action -eq "logoff") {
        logoff
    }
} else {
    # Log allowed time (only once per hour)
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
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Current time is in allowed window for $currentDay"
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
        (Get-Date).ToString() | Set-Content $lastLogFile -Encoding UTF8
    }
}
