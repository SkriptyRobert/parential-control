# Night Shutdown - After midnight and before 6:00
# Runs via Scheduled Task as SYSTEM

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\time-limits.json"
)

# Load configuration
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $nightConfig = $config.nightShutdown
} else {
    # Default values
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

# Get current time
$currentTime = Get-Date
$currentHour = $currentTime.Hour
$currentMinute = $currentTime.Minute

# Parse time from configuration
$startTimeParts = $nightConfig.startTime.Split(':')
$endTimeParts = $nightConfig.endTime.Split(':')
$startHour = [int]$startTimeParts[0]
$startMinute = [int]$startTimeParts[1]
$endHour = [int]$endTimeParts[0]
$endMinute = [int]$endTimeParts[1]

# Check if we are in the night time window
$shouldShutdown = $false

if ($startHour -lt $endHour) {
    # Normal case: 00:00 - 06:00
    $currentMinutes = $currentHour * 60 + $currentMinute
    $startMinutes = $startHour * 60 + $startMinute
    $endMinutes = $endHour * 60 + $endMinute
    
    if ($currentMinutes -ge $startMinutes -and $currentMinutes -lt $endMinutes) {
        $shouldShutdown = $true
    }
} else {
    # Overlapping day (e.g. 22:00 - 06:00)
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
    
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Night shutdown: Current time $($currentTime.ToString('HH:mm')) is in forbidden window ($($nightConfig.startTime) - $($nightConfig.endTime))"
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
    
    # Check if someone is logged in
    $loggedInUsers = quser 2>$null
    if ($loggedInUsers) {
        # Shutdown PC with warning
        $message = "Parental Control: Computer will shut down due to night usage ban ($($nightConfig.startTime) - $($nightConfig.endTime)). Shutdown in 60 seconds."
        
        # Display warning to all logged in users
        $loggedInUsers | ForEach-Object {
            if ($_ -match '^(\S+)') {
                $username = $matches[1]
                if ($username -ne 'USERNAME') {
                    try {
                        # Use msg.exe to display message (requires proper permissions)
                        msg $username "$message" 2>$null
                    } catch {
                        # Fallback - logging
                        Add-Content -Path $logFile -Value "Cannot display message to user $username" -Encoding UTF8
                    }
                }
            }
        }
        
        Start-Sleep -Seconds 60
    }
    
    # Shutdown PC
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Shutting down PC..." -Encoding UTF8
    
    if ($nightConfig.action -eq "shutdown") {
        Stop-Computer -Force
    } elseif ($nightConfig.action -eq "logoff") {
        logoff
    }
}
