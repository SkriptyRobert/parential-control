# Setup Scheduled Tasks for automatic control execution
# Requires administrator privileges

param(
    [Parameter(Mandatory=$false)]
    [string]$ScriptsPath = "$PSScriptRoot"
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

Write-Host "`n=== Setting up Scheduled Tasks - Parental Control ===" -ForegroundColor Cyan

# Path to PowerShell
$powershellPath = (Get-Command powershell.exe).Source

# Function to create or update Scheduled Task
function Setup-ScheduledTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$Description,
        [string]$Schedule,
        [int]$IntervalMinutes = 0
    )
    
    # Remove existing task
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Removed existing task: $TaskName" -ForegroundColor Yellow
    }
    
    # Create action
    $action = New-ScheduledTaskAction -Execute $powershellPath -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -WorkingDirectory (Split-Path $ScriptPath -Parent)
    
    # Create trigger based on type
    $trigger = $null
    
    switch ($Schedule) {
        "AtStartup" {
            $trigger = New-ScheduledTaskTrigger -AtStartup
        }
        "AtLogon" {
            $trigger = New-ScheduledTaskTrigger -AtLogOn
        }
        "Daily" {
            $trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
        }
        "Interval" {
            if ($IntervalMinutes -gt 0) {
                $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 365)
            }
        }
        "Hourly" {
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365)
        }
    }
    
    # Settings for running as SYSTEM
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false
    
    # Create task
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $Description -ErrorAction Stop | Out-Null
        Write-Host "Created task: $TaskName" -ForegroundColor Green
    }
    catch {
        Write-Error "Error creating task $TaskName : $_"
    }
}

# 1. Night shutdown - every 15 minutes during night
$nightShutdownScript = Join-Path $ScriptsPath "night-shutdown.ps1"
if (Test-Path $nightShutdownScript) {
    Setup-ScheduledTask -TaskName "ParentalControl-NightShutdown" `
        -ScriptPath $nightShutdownScript `
        -Description "Parental Control - Night shutdown PC (after midnight and before 6:00)" `
        -Schedule "Interval" `
        -IntervalMinutes 15
} else {
    Write-Warning "Script not found: $nightShutdownScript"
}

# 2. Daily limits - every 5 minutes
$dailyLimitScript = Join-Path $ScriptsPath "daily-limit.ps1"
if (Test-Path $dailyLimitScript) {
    Setup-ScheduledTask -TaskName "ParentalControl-DailyLimit" `
        -ScriptPath $dailyLimitScript `
        -Description "Parental Control - Monitor daily usage time limits" `
        -Schedule "Interval" `
        -IntervalMinutes 5
} else {
    Write-Warning "Script not found: $dailyLimitScript"
}

# 3. Schedule control - every 5 minutes
$scheduleControlScript = Join-Path $ScriptsPath "schedule-control.ps1"
if (Test-Path $scheduleControlScript) {
    Setup-ScheduledTask -TaskName "ParentalControl-Schedule" `
        -ScriptPath $scheduleControlScript `
        -Description "Parental Control - Check time schedule" `
        -Schedule "Interval" `
        -IntervalMinutes 5
} else {
    Write-Warning "Script not found: $scheduleControlScript"
}

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "All Scheduled Tasks have been set up." -ForegroundColor Green
Write-Host "`nTo check run: Get-ScheduledTask -TaskName 'ParentalControl-*'" -ForegroundColor Cyan
