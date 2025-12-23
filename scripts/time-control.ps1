# Time Control - Unified Time Management
# Combines: daily-limit, night-shutdown, schedule-control
#
# Usage:
#   .\time-control.ps1                    # Interactive wizard
#   .\time-control.ps1 -Check             # Run time checks (for scheduled task)
#   .\time-control.ps1 -ShowStatus        # Show current usage
#   .\time-control.ps1 -Configure         # Configure settings
#   .\time-control.ps1 -StatusJson        # Output status as JSON (for web API)

param(
    [switch]$Check,
    [switch]$ShowStatus,
    [switch]$Configure,
    [switch]$StatusJson,
    [string]$ConfigPath = "$PSScriptRoot\..\config\time-limits.json"
)

# Helper: Convert PSCustomObject to Hashtable
function ConvertTo-Hashtable {
    param($Object)
    if ($Object -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $Object.Keys) { $hash[$key] = ConvertTo-Hashtable $Object[$key] }
        return $hash
    }
    elseif ($Object -is [System.Array]) {
        return $Object | ForEach-Object { ConvertTo-Hashtable $_ }
    }
    elseif ($Object -is [PSCustomObject]) {
        $hash = @{}
        $Object.PSObject.Properties | ForEach-Object { $hash[$_.Name] = ConvertTo-Hashtable $_.Value }
        return $hash
    }
    return $Object
}

# Load configuration
function Get-TimeConfig {
    $defaultConfig = @{
        excludedUsers = @("rdpuser", "Administrator", "SYSTEM")
        dailyLimit = @{ enabled = $true; hours = 2; warningAtMinutes = 15; action = "shutdown" }
        nightShutdown = @{ enabled = $true; startTime = "00:00"; endTime = "06:00"; action = "shutdown" }
        schedule = @{
            enabled = $true
            allowedWindows = @(
                @{day = "Monday"; start = "15:00"; end = "20:00"}
                @{day = "Tuesday"; start = "15:00"; end = "20:00"}
                @{day = "Wednesday"; start = "15:00"; end = "20:00"}
                @{day = "Thursday"; start = "15:00"; end = "20:00"}
                @{day = "Friday"; start = "15:00"; end = "21:00"}
                @{day = "Saturday"; start = "09:00"; end = "21:00"}
                @{day = "Sunday"; start = "09:00"; end = "20:00"}
            )
            action = "shutdown"
        }
        trackingFile = "C:\ProgramData\ParentalControl\usage-tracking.json"
    }
    
    if (Test-Path $ConfigPath) {
        try {
            $loaded = Get-Content $ConfigPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
            foreach ($key in $loaded.Keys) { $defaultConfig[$key] = $loaded[$key] }
        } catch {}
    }
    return $defaultConfig
}

function Save-TimeConfig {
    param($Config)
    $configDir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    $Config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
}

function Get-ActiveUsers {
    param($Config)
    $users = @()
    $quser = quser 2>$null
    if ($quser) {
        foreach ($line in $quser) {
            if ($line -match '^\s*(\S+)') {
                $username = $matches[1]
                if ($username -ne 'USERNAME' -and $username -notin $Config.excludedUsers) {
                    $users += $username
                }
            }
        }
    }
    return $users
}

# JSON Status output (for web API)
function Get-StatusAsJson {
    $config = Get-TimeConfig
    $now = Get-Date
    $today = Get-Date -Format "yyyy-MM-dd"
    
    # Get usage data
    $usedMinutes = 0
    $trackingFile = $config.trackingFile
    if (Test-Path $trackingFile) {
        try {
            $data = Get-Content $trackingFile -Raw | ConvertFrom-Json
            if ($data.$today) { $usedMinutes = $data.$today.totalMinutes }
        } catch {}
    }
    
    $limitMinutes = $config.dailyLimit.hours * 60
    $remaining = [math]::Max(0, $limitMinutes - $usedMinutes)
    
    # Schedule check
    $dayName = $now.DayOfWeek.ToString()
    $todayWindow = $config.schedule.allowedWindows | Where-Object { $_.day -eq $dayName }
    $withinSchedule = $false
    if ($todayWindow) {
        $currentMinutes = $now.Hour * 60 + $now.Minute
        $startMinutes = [DateTime]::ParseExact($todayWindow.start, "HH:mm", $null).Hour * 60 + [DateTime]::ParseExact($todayWindow.start, "HH:mm", $null).Minute
        $endMinutes = [DateTime]::ParseExact($todayWindow.end, "HH:mm", $null).Hour * 60 + [DateTime]::ParseExact($todayWindow.end, "HH:mm", $null).Minute
        $withinSchedule = ($currentMinutes -ge $startMinutes -and $currentMinutes -lt $endMinutes)
    }
    
    @{
        timestamp = $now.ToString("o")
        computer = $env:COMPUTERNAME
        dailyLimit = @{
            enabled = $config.dailyLimit.enabled
            limitHours = $config.dailyLimit.hours
            usedMinutes = [math]::Round($usedMinutes)
            remainingMinutes = [math]::Round($remaining)
        }
        nightShutdown = @{
            enabled = $config.nightShutdown.enabled
            startTime = $config.nightShutdown.startTime
            endTime = $config.nightShutdown.endTime
        }
        schedule = @{
            enabled = $config.schedule.enabled
            todayWindow = if ($todayWindow) { "$($todayWindow.start)-$($todayWindow.end)" } else { "none" }
            withinSchedule = $withinSchedule
        }
        excludedUsers = $config.excludedUsers
        activeUsers = Get-ActiveUsers -Config $config
    } | ConvertTo-Json -Depth 5
}

# Check mode (for scheduled task)
function Invoke-TimeCheck {
    $config = Get-TimeConfig
    $activeUsers = Get-ActiveUsers -Config $config
    if ($activeUsers.Count -eq 0) { exit 0 }
    
    $logFile = "C:\ProgramData\ParentalControl\time-control.log"
    $logDir = Split-Path $logFile -Parent
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    
    $now = Get-Date
    $shouldShutdown = $false
    $shutdownReason = ""
    
    # Night check
    if ($config.nightShutdown.enabled) {
        $currentMinutes = $now.Hour * 60 + $now.Minute
        $startMinutes = [DateTime]::ParseExact($config.nightShutdown.startTime, "HH:mm", $null).Hour * 60 + [DateTime]::ParseExact($config.nightShutdown.startTime, "HH:mm", $null).Minute
        $endMinutes = [DateTime]::ParseExact($config.nightShutdown.endTime, "HH:mm", $null).Hour * 60 + [DateTime]::ParseExact($config.nightShutdown.endTime, "HH:mm", $null).Minute
        
        $isNight = if ($startMinutes -gt $endMinutes) {
            ($currentMinutes -ge $startMinutes) -or ($currentMinutes -lt $endMinutes)
        } else {
            ($currentMinutes -ge $startMinutes) -and ($currentMinutes -lt $endMinutes)
        }
        
        if ($isNight) {
            $shouldShutdown = $true
            $shutdownReason = "Night time"
        }
    }
    
    # Schedule check
    if (-not $shouldShutdown -and $config.schedule.enabled) {
        $dayName = $now.DayOfWeek.ToString()
        $todayWindow = $config.schedule.allowedWindows | Where-Object { $_.day -eq $dayName }
        
        if ($todayWindow) {
            $currentMinutes = $now.Hour * 60 + $now.Minute
            $startMinutes = [DateTime]::ParseExact($todayWindow.start, "HH:mm", $null).Hour * 60 + [DateTime]::ParseExact($todayWindow.start, "HH:mm", $null).Minute
            $endMinutes = [DateTime]::ParseExact($todayWindow.end, "HH:mm", $null).Hour * 60 + [DateTime]::ParseExact($todayWindow.end, "HH:mm", $null).Minute
            
            if ($currentMinutes -lt $startMinutes -or $currentMinutes -ge $endMinutes) {
                $shouldShutdown = $true
                $shutdownReason = "Outside schedule"
            }
        } else {
            $shouldShutdown = $true
            $shutdownReason = "No schedule for $dayName"
        }
    }
    
    # Daily limit check
    if (-not $shouldShutdown -and $config.dailyLimit.enabled) {
        $trackingFile = $config.trackingFile
        $trackingDir = Split-Path $trackingFile -Parent
        if (-not (Test-Path $trackingDir)) { New-Item -ItemType Directory -Path $trackingDir -Force | Out-Null }
        
        $today = Get-Date -Format "yyyy-MM-dd"
        $trackingData = @{}
        if (Test-Path $trackingFile) {
            try { $trackingData = Get-Content $trackingFile -Raw | ConvertFrom-Json | ConvertTo-Hashtable } catch {}
        }
        
        if (-not $trackingData.ContainsKey($today)) {
            $trackingData[$today] = @{ totalMinutes = 0; lastCheck = (Get-Date).ToString("o"); warned = $false }
        }
        
        $todayData = $trackingData[$today]
        try {
            $elapsed = ((Get-Date) - [DateTime]::Parse($todayData.lastCheck)).TotalMinutes
            if ($elapsed -gt 0 -and $elapsed -lt 30) { $todayData.totalMinutes += $elapsed }
        } catch {}
        
        $todayData.lastCheck = (Get-Date).ToString("o")
        $remaining = ($config.dailyLimit.hours * 60) - $todayData.totalMinutes
        
        if ($remaining -le $config.dailyLimit.warningAtMinutes -and $remaining -gt 0 -and -not $todayData.warned) {
            foreach ($user in $activeUsers) { msg $user "Parental Control: $([math]::Round($remaining)) min remaining!" 2>$null }
            $todayData.warned = $true
        }
        
        if ($remaining -le 0) {
            $shouldShutdown = $true
            $shutdownReason = "Daily limit reached"
        }
        
        $trackingData[$today] = $todayData
        $trackingData | ConvertTo-Json -Depth 10 | Set-Content $trackingFile -Encoding UTF8
    }
    
    if ($shouldShutdown) {
        $msg = "Parental Control: $shutdownReason. Shutdown in 60s."
        Add-Content -Path $logFile -Value "$(Get-Date) - $msg" -Encoding UTF8
        foreach ($user in $activeUsers) { msg $user $msg 2>$null }
        Start-Sleep -Seconds 60
        Stop-Computer -Force
    }
}

# Interactive status
function Show-TimeStatus {
    Write-Host "`n=== Time Control Status ===" -ForegroundColor Cyan
    $config = Get-TimeConfig
    $now = Get-Date
    
    Write-Host "`nCurrent: $($now.ToString('yyyy-MM-dd HH:mm')) ($($now.DayOfWeek))" -ForegroundColor White
    
    if ($config.dailyLimit.enabled) {
        $today = Get-Date -Format "yyyy-MM-dd"
        $usedMinutes = 0
        if (Test-Path $config.trackingFile) {
            try { $data = Get-Content $config.trackingFile -Raw | ConvertFrom-Json; $usedMinutes = $data.$today.totalMinutes } catch {}
        }
        $remaining = [math]::Max(0, ($config.dailyLimit.hours * 60) - $usedMinutes)
        Write-Host "`nDaily Limit: $($config.dailyLimit.hours)h | Used: $([math]::Round($usedMinutes))m | Remaining: $([math]::Round($remaining))m" -ForegroundColor $(if ($remaining -gt 30) {"Green"} else {"Yellow"})
    }
    
    if ($config.nightShutdown.enabled) {
        Write-Host "Night: $($config.nightShutdown.startTime) - $($config.nightShutdown.endTime)" -ForegroundColor Gray
    }
    
    Write-Host "Excluded: $($config.excludedUsers -join ', ')" -ForegroundColor Gray
}

# Main
if ($StatusJson) { Get-StatusAsJson }
elseif ($Check) { Invoke-TimeCheck }
elseif ($ShowStatus) { Show-TimeStatus }
elseif ($Configure) {
    Write-Host "Use web interface or edit: $ConfigPath" -ForegroundColor Yellow
    notepad $ConfigPath
}
else {
    Write-Host "`nTime Control - Options:" -ForegroundColor Cyan
    Write-Host "  -ShowStatus   Show current status"
    Write-Host "  -StatusJson   Output as JSON (for API)"
    Write-Host "  -Configure    Edit configuration"
    Write-Host "  -Check        Run time check"
}
