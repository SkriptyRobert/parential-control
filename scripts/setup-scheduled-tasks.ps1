# Nastavení Scheduled Tasks pro automatické spouštění kontrol
# Vyžaduje administrátorská práva

param(
    [Parameter(Mandatory=$false)]
    [string]$ScriptsPath = "$PSScriptRoot"
)

# Kontrola administrátorských práv
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Tento skript vyžaduje administrátorská práva!"
    exit 1
}

Write-Host "`n=== Nastavení Scheduled Tasks - Parental Control ===" -ForegroundColor Cyan

# Cesta k PowerShell
$powershellPath = (Get-Command powershell.exe).Source

# Funkce pro vytvoření nebo aktualizaci Scheduled Task
function Setup-ScheduledTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$Description,
        [string]$Schedule,
        [int]$IntervalMinutes = 0
    )
    
    # Odstranění existujícího tasku
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Odstraněn existující task: $TaskName" -ForegroundColor Yellow
    }
    
    # Vytvoření akce
    $action = New-ScheduledTaskAction -Execute $powershellPath -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -WorkingDirectory (Split-Path $ScriptPath -Parent)
    
    # Vytvoření triggeru podle typu
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
    
    # Nastavení pro spuštění jako SYSTEM
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Nastavení
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false
    
    # Vytvoření tasku
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $Description -ErrorAction Stop | Out-Null
        Write-Host "Vytvořen task: $TaskName" -ForegroundColor Green
    }
    catch {
        Write-Error "Chyba při vytváření tasku $TaskName : $_"
    }
}

# 1. Noční vypínání - každou hodinu v noci
$nightShutdownScript = Join-Path $ScriptsPath "night-shutdown.ps1"
if (Test-Path $nightShutdownScript) {
    Setup-ScheduledTask -TaskName "ParentalControl-NightShutdown" `
        -ScriptPath $nightShutdownScript `
        -Description "Rodičovská kontrola - Noční vypínání PC (po půlnoci a před 6:00)" `
        -Schedule "Interval" `
        -IntervalMinutes 15
} else {
    Write-Warning "Skript nenalezen: $nightShutdownScript"
}

# 2. Denní limity - každých 5 minut
$dailyLimitScript = Join-Path $ScriptsPath "daily-limit.ps1"
if (Test-Path $dailyLimitScript) {
    Setup-ScheduledTask -TaskName "ParentalControl-DailyLimit" `
        -ScriptPath $dailyLimitScript `
        -Description "Rodičovská kontrola - Sledování denních limitů času použití" `
        -Schedule "Interval" `
        -IntervalMinutes 5
} else {
    Write-Warning "Skript nenalezen: $dailyLimitScript"
}

# 3. Časový rozvrh - každých 5 minut
$scheduleControlScript = Join-Path $ScriptsPath "schedule-control.ps1"
if (Test-Path $scheduleControlScript) {
    Setup-ScheduledTask -TaskName "ParentalControl-Schedule" `
        -ScriptPath $scheduleControlScript `
        -Description "Rodičovská kontrola - Kontrola časového rozvrhu" `
        -Schedule "Interval" `
        -IntervalMinutes 5
} else {
    Write-Warning "Skript nenalezen: $scheduleControlScript"
}

Write-Host "`n=== Hotovo ===" -ForegroundColor Green
Write-Host "Všechny Scheduled Tasks byly nastaveny." -ForegroundColor Green
Write-Host "`nPro kontrolu spusťte: Get-ScheduledTask -TaskName 'ParentalControl-*'" -ForegroundColor Cyan

