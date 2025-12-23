# App Limits - Per-Application Time Limits
# Dynamically detects installed apps and tracks usage
#
# Usage:
#   .\app-limits.ps1                    # Interactive
#   .\app-limits.ps1 -Detect            # Detect apps
#   .\app-limits.ps1 -Check             # Check limits (scheduled task)
#   .\app-limits.ps1 -Status            # Show usage
#   .\app-limits.ps1 -StatusJson        # JSON output for API
#   .\app-limits.ps1 -DetectJson        # Detected apps as JSON

param(
    [switch]$Detect,
    [switch]$Check,
    [switch]$Status,
    [switch]$StatusJson,
    [switch]$DetectJson,
    [switch]$Configure,
    [string]$ConfigPath = "$PSScriptRoot\..\config\app-limits.json"
)

$TrackingFile = "C:\ProgramData\ParentalControl\app-tracking.json"
$LogFile = "C:\ProgramData\ParentalControl\app-limits.log"

# Efficient app detection - searches common locations
function Find-InstalledApps {
    $apps = @()
    
    # Common install locations
    $searchPaths = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:LOCALAPPDATA",
        "$env:APPDATA",
        "$env:USERPROFILE\Desktop"
    )
    
    # Known app patterns - process name : display name : category
    $knownApps = @{
        # Games
        "FortniteClient*" = @("Fortnite", "Games")
        "RobloxPlayerBeta" = @("Roblox", "Games")
        "Minecraft*" = @("Minecraft", "Games")
        "steam" = @("Steam", "Games")
        "EpicGamesLauncher" = @("Epic Games", "Games")
        "Battle.net" = @("Battle.net", "Games")
        "LeagueClient*" = @("League of Legends", "Games")
        "valorant*" = @("Valorant", "Games")
        "GTA5" = @("GTA V", "Games")
        "csgo" = @("CS:GO", "Games")
        
        # Social
        "Discord" = @("Discord", "Social")
        "WhatsApp" = @("WhatsApp", "Social")
        "Telegram" = @("Telegram", "Social")
        "Messenger" = @("Messenger", "Social")
        "Skype" = @("Skype", "Social")
        "Slack" = @("Slack", "Social")
        "Teams" = @("Microsoft Teams", "Social")
        "Zoom" = @("Zoom", "Social")
        
        # Media
        "Spotify" = @("Spotify", "Media")
        "vlc" = @("VLC", "Media")
        "Netflix" = @("Netflix", "Media")
        
        # Browsers
        "chrome" = @("Chrome", "Browser")
        "firefox" = @("Firefox", "Browser")
        "msedge" = @("Edge", "Browser")
        "opera" = @("Opera", "Browser")
        "brave" = @("Brave", "Browser")
    }
    
    # Method 1: Check running processes
    $runningProcs = Get-Process -ErrorAction SilentlyContinue | 
        Where-Object { $_.MainWindowTitle -ne "" -or $_.Path } |
        Select-Object ProcessName, Path, @{N='Memory';E={[math]::Round($_.WS/1MB,1)}} -Unique
    
    foreach ($proc in $runningProcs) {
        foreach ($pattern in $knownApps.Keys) {
            if ($proc.ProcessName -like $pattern) {
                $info = $knownApps[$pattern]
                $apps += @{
                    name = $info[0]
                    category = $info[1]
                    processName = $proc.ProcessName
                    path = $proc.Path
                    running = $true
                    memory = $proc.Memory
                }
                break
            }
        }
    }
    
    # Method 2: Search for .exe files in common locations
    $exePatterns = @(
        "*Discord*.exe", "*Fortnite*.exe", "*Roblox*.exe", "*Steam*.exe",
        "*Epic*.exe", "*Minecraft*.exe", "*WhatsApp*.exe", "*Telegram*.exe",
        "*Spotify*.exe", "*Battle.net*.exe", "*League*.exe"
    )
    
    foreach ($searchPath in $searchPaths) {
        if (-not (Test-Path $searchPath)) { continue }
        
        foreach ($pattern in $exePatterns) {
            $found = Get-ChildItem -Path $searchPath -Filter $pattern -Recurse -ErrorAction SilentlyContinue -Depth 3 |
                Select-Object -First 1
            
            if ($found) {
                $baseName = $found.BaseName -replace '[^a-zA-Z]', ''
                $alreadyFound = $apps | Where-Object { $_.path -eq $found.FullName }
                
                if (-not $alreadyFound) {
                    # Try to match with known apps
                    $matched = $false
                    foreach ($procPattern in $knownApps.Keys) {
                        if ($found.BaseName -like "*$($procPattern.Replace('*',''))*") {
                            $info = $knownApps[$procPattern]
                            $apps += @{
                                name = $info[0]
                                category = $info[1]
                                processName = $found.BaseName
                                path = $found.FullName
                                running = $false
                            }
                            $matched = $true
                            break
                        }
                    }
                    
                    if (-not $matched) {
                        $apps += @{
                            name = $found.BaseName
                            category = "Other"
                            processName = $found.BaseName
                            path = $found.FullName
                            running = $false
                        }
                    }
                }
            }
        }
    }
    
    # Method 3: Check Windows Apps (UWP) - for things like Netflix, WhatsApp
    try {
        $uwpApps = Get-AppxPackage -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -match "Netflix|WhatsApp|Spotify|Messenger|TikTok|Instagram" } |
            Select-Object Name, PackageFamilyName
        
        foreach ($uwp in $uwpApps) {
            $displayName = $uwp.Name -replace '.*\.', ''
            $apps += @{
                name = $displayName
                category = "UWP App"
                processName = $uwp.PackageFamilyName
                path = "UWP:$($uwp.Name)"
                running = $false
                isUwp = $true
            }
        }
    } catch {}
    
    # Remove duplicates by name
    $uniqueApps = @{}
    foreach ($app in $apps) {
        if (-not $uniqueApps.ContainsKey($app.name)) {
            $uniqueApps[$app.name] = $app
        } elseif ($app.running) {
            $uniqueApps[$app.name] = $app  # Prefer running instance
        }
    }
    
    return $uniqueApps.Values | Sort-Object category, name
}

# Load/Save config
function Get-AppConfig {
    if (Test-Path $ConfigPath) {
        try { return Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch {}
    }
    return @{ enabled = $true; limits = @() }
}

function Save-AppConfig {
    param($Config)
    $dir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
}

# Load/Save tracking
function Get-Tracking {
    if (Test-Path $TrackingFile) {
        try { return Get-Content $TrackingFile -Raw | ConvertFrom-Json } catch {}
    }
    return @{}
}

function Save-Tracking {
    param($Data)
    $dir = Split-Path $TrackingFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Data | ConvertTo-Json -Depth 10 | Set-Content $TrackingFile -Encoding UTF8
}

# Check app limits (for scheduled task)
function Invoke-AppCheck {
    $config = Get-AppConfig
    if (-not $config.enabled -or $config.limits.Count -eq 0) { exit 0 }
    
    $today = Get-Date -Format "yyyy-MM-dd"
    $tracking = Get-Tracking
    if (-not $tracking.$today) { $tracking | Add-Member -NotePropertyName $today -NotePropertyValue @{} -Force }
    
    foreach ($limit in $config.limits) {
        $appName = $limit.name
        $processName = $limit.processName -replace '\*', ''
        $limitMinutes = $limit.dailyMinutes
        
        # Initialize tracking
        if (-not $tracking.$today.$appName) {
            $tracking.$today | Add-Member -NotePropertyName $appName -NotePropertyValue @{
                totalMinutes = 0
                lastCheck = $null
                warned = $false
                killed = $false
            } -Force
        }
        
        $appTrack = $tracking.$today.$appName
        
        # Check if running
        $proc = Get-Process -Name $processName -ErrorAction SilentlyContinue
        
        if ($proc) {
            # Add elapsed time
            if ($appTrack.lastCheck) {
                try {
                    $elapsed = ((Get-Date) - [DateTime]::Parse($appTrack.lastCheck)).TotalMinutes
                    if ($elapsed -gt 0 -and $elapsed -lt 10) {
                        $appTrack.totalMinutes += $elapsed
                    }
                } catch {}
            }
            $appTrack.lastCheck = (Get-Date).ToString("o")
            
            $remaining = $limitMinutes - $appTrack.totalMinutes
            
            # Warning
            $warnAt = if ($limit.warningAtMinutes) { $limit.warningAtMinutes } else { 5 }
            if ($remaining -le $warnAt -and $remaining -gt 0 -and -not $appTrack.warned) {
                msg * "Parental Control: $appName has $([math]::Round($remaining)) min left!" 2>$null
                $appTrack.warned = $true
                Add-Content -Path $LogFile -Value "$(Get-Date) - WARNING: $appName" -Encoding UTF8
            }
            
            # Kill if over limit
            if ($remaining -le 0 -and -not $appTrack.killed) {
                msg * "Parental Control: $appName limit reached. Closing..." 2>$null
                Start-Sleep -Seconds 5
                $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                $appTrack.killed = $true
                Add-Content -Path $LogFile -Value "$(Get-Date) - KILLED: $appName" -Encoding UTF8
            }
        } else {
            $appTrack.lastCheck = $null
        }
        
        $tracking.$today.$appName = $appTrack
    }
    
    Save-Tracking -Data $tracking
}

# Status as JSON (for API)
function Get-StatusAsJson {
    $config = Get-AppConfig
    $today = Get-Date -Format "yyyy-MM-dd"
    $tracking = Get-Tracking
    
    $status = @{
        timestamp = (Get-Date).ToString("o")
        enabled = $config.enabled
        apps = @()
    }
    
    foreach ($limit in $config.limits) {
        $appName = $limit.name
        $usedMinutes = 0
        $warned = $false
        $killed = $false
        
        if ($tracking.$today.$appName) {
            $usedMinutes = $tracking.$today.$appName.totalMinutes
            $warned = $tracking.$today.$appName.warned
            $killed = $tracking.$today.$appName.killed
        }
        
        # Check if running
        $processName = $limit.processName -replace '\*', ''
        $running = $null -ne (Get-Process -Name $processName -ErrorAction SilentlyContinue)
        
        $status.apps += @{
            name = $appName
            category = $limit.category
            limitMinutes = $limit.dailyMinutes
            usedMinutes = [math]::Round($usedMinutes)
            remainingMinutes = [math]::Max(0, $limit.dailyMinutes - $usedMinutes)
            running = $running
            warned = $warned
            killed = $killed
        }
    }
    
    $status | ConvertTo-Json -Depth 5
}

# Detected apps as JSON
function Get-DetectedAsJson {
    $apps = Find-InstalledApps
    @{
        timestamp = (Get-Date).ToString("o")
        computer = $env:COMPUTERNAME
        apps = $apps
    } | ConvertTo-Json -Depth 5
}

# Show status
function Show-Status {
    Write-Host "`n=== App Limits Status ===" -ForegroundColor Cyan
    
    $config = Get-AppConfig
    $today = Get-Date -Format "yyyy-MM-dd"
    $tracking = Get-Tracking
    
    if ($config.limits.Count -eq 0) {
        Write-Host "No app limits configured." -ForegroundColor Yellow
        Write-Host "Run: .\app-limits.ps1 -Detect" -ForegroundColor Gray
        return
    }
    
    foreach ($limit in $config.limits) {
        $appName = $limit.name
        $limitMin = $limit.dailyMinutes
        $usedMin = 0
        
        if ($tracking.$today.$appName) {
            $usedMin = [math]::Round($tracking.$today.$appName.totalMinutes)
        }
        
        $remaining = [math]::Max(0, $limitMin - $usedMin)
        $color = if ($remaining -le 0) { "Red" } elseif ($remaining -le 10) { "Yellow" } else { "Green" }
        
        $processName = $limit.processName -replace '\*', ''
        $running = if (Get-Process -Name $processName -ErrorAction SilentlyContinue) { "[RUNNING]" } else { "" }
        
        Write-Host "`n$appName $running" -ForegroundColor White
        Write-Host "  Limit: ${limitMin}m | Used: ${usedMin}m | Left: " -NoNewline
        Write-Host "${remaining}m" -ForegroundColor $color
    }
}

# Detect and show apps
function Show-DetectedApps {
    Write-Host "`n=== Detected Applications ===" -ForegroundColor Cyan
    Write-Host "Scanning..." -ForegroundColor Gray
    
    $apps = Find-InstalledApps
    $categories = $apps | Group-Object { $_.category }
    
    foreach ($cat in $categories | Sort-Object Name) {
        Write-Host "`n$($cat.Name):" -ForegroundColor Yellow
        foreach ($app in $cat.Group) {
            $status = if ($app.running) { "[RUNNING]" } else { "" }
            Write-Host "  $($app.name) $status" -ForegroundColor $(if ($app.running) { "Green" } else { "White" })
            Write-Host "    Process: $($app.processName)" -ForegroundColor Gray
        }
    }
    
    Write-Host "`nTotal: $($apps.Count) apps found" -ForegroundColor Cyan
}

# Main
if ($DetectJson) { Get-DetectedAsJson }
elseif ($StatusJson) { Get-StatusAsJson }
elseif ($Detect) { Show-DetectedApps }
elseif ($Check) { Invoke-AppCheck }
elseif ($Status) { Show-Status }
elseif ($Configure) {
    Write-Host "Use web interface or edit: $ConfigPath" -ForegroundColor Yellow
    notepad $ConfigPath
}
else {
    Write-Host "`nApp Limits - Options:" -ForegroundColor Cyan
    Write-Host "  -Detect       Detect installed apps"
    Write-Host "  -DetectJson   Detected apps as JSON"
    Write-Host "  -Status       Show usage status"
    Write-Host "  -StatusJson   Status as JSON (for API)"
    Write-Host "  -Configure    Edit configuration"
    Write-Host "  -Check        Run limit check"
}
