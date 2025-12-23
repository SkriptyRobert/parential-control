# Windows Firewall Rules - Block Applications
# Requires administrator privileges

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\apps-to-block.json",
    
    [Parameter(Mandatory=$false)]
    [switch]$Remove
)

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges!"
    exit 1
}

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json

# Function to expand environment variables in path (handles %VAR% format)
function Expand-EnvPath {
    param([string]$Path)
    
    # Expand Windows-style %VAR% variables
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    return $expanded
}

function Block-Application {
    param(
        [string]$AppName,
        [string[]]$ProcessNames,
        [string[]]$Paths
    )
    
    # Sanitize app name for rule naming (remove special chars)
    $safeAppName = $AppName -replace '[^a-zA-Z0-9_-]', ''
    $ruleName = "ParentalControl-Block-$safeAppName"
    
    if ($Remove) {
        # Remove rules
        $existingRules = Get-NetFirewallRule -DisplayName "$ruleName*" -ErrorAction SilentlyContinue
        if ($existingRules) {
            $existingRules | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            Write-Host "Removed rules for: $AppName" -ForegroundColor Yellow
        }
        return
    }
    
    # Check if rule already exists
    $existingRule = Get-NetFirewallRule -DisplayName "$ruleName-Out-*" -ErrorAction SilentlyContinue
    if ($existingRule) {
        Write-Host "Rules already exist for: $AppName" -ForegroundColor Yellow
        return
    }
    
    $rulesCreated = 0
    
    # Create rules for specific paths first (more reliable)
    foreach ($path in $Paths) {
        # Expand environment variables (%APPDATA%, %LOCALAPPDATA%, etc.)
        $expandedPath = Expand-EnvPath -Path $path
        
        if ([string]::IsNullOrEmpty($expandedPath)) {
            continue
        }
        
        # Check if path exists
        if (Test-Path $expandedPath -ErrorAction SilentlyContinue) {
            try {
                $fileName = [System.IO.Path]::GetFileName($expandedPath)
                $safeFileName = $fileName -replace '[^a-zA-Z0-9_.-]', ''
                
                if ($config.blockOutbound -or $config.blockAllMatching) {
                    New-NetFirewallRule -DisplayName "$ruleName-Out-$safeFileName" `
                        -Direction Outbound `
                        -Program $expandedPath `
                        -Action Block `
                        -Profile Any `
                        -Enabled True `
                        -ErrorAction Stop | Out-Null
                    $rulesCreated++
                }
                
                if ($config.blockInbound) {
                    New-NetFirewallRule -DisplayName "$ruleName-In-$safeFileName" `
                        -Direction Inbound `
                        -Program $expandedPath `
                        -Action Block `
                        -Profile Any `
                        -Enabled True `
                        -ErrorAction Stop | Out-Null
                    $rulesCreated++
                }
                
                Write-Host "Created rule for: $AppName ($expandedPath)" -ForegroundColor Green
            }
            catch {
                Write-Warning "Error creating rule for path $expandedPath : $_"
            }
        }
    }
    
    # If no path rules created, try process name approach (less reliable but wider coverage)
    if ($rulesCreated -eq 0) {
        foreach ($processName in $ProcessNames) {
            # Sanitize process name
            $safeProcessName = $processName -replace '[^a-zA-Z0-9_.-]', ''
            if ([string]::IsNullOrEmpty($safeProcessName)) { continue }
            
            # Find running process to get actual path
            $process = Get-Process -Name ($processName -replace '\.exe$', '') -ErrorAction SilentlyContinue | Select-Object -First 1
            
            if ($process -and $process.Path) {
                try {
                    if ($config.blockOutbound -or $config.blockAllMatching) {
                        New-NetFirewallRule -DisplayName "$ruleName-Out-$safeProcessName" `
                            -Direction Outbound `
                            -Program $process.Path `
                            -Action Block `
                            -Profile Any `
                            -Enabled True `
                            -ErrorAction Stop | Out-Null
                    }
                    
                    if ($config.blockInbound) {
                        New-NetFirewallRule -DisplayName "$ruleName-In-$safeProcessName" `
                            -Direction Inbound `
                            -Program $process.Path `
                            -Action Block `
                            -Profile Any `
                            -Enabled True `
                            -ErrorAction Stop | Out-Null
                    }
                    
                    Write-Host "Created rule from running process: $AppName ($($process.Path))" -ForegroundColor Green
                }
                catch {
                    Write-Warning "Error creating rule for $processName : $_"
                }
            } else {
                Write-Host "App not installed or not running: $AppName (will be blocked when path is found)" -ForegroundColor DarkYellow
            }
        }
    }
}

# Process all applications
Write-Host "`n=== Windows Firewall Rules - Parental Control ===" -ForegroundColor Cyan
Write-Host "Configuration: $ConfigPath" -ForegroundColor Cyan
Write-Host "Action: $(if ($Remove) { 'Remove' } else { 'Create' })`n" -ForegroundColor Cyan

foreach ($app in $config.applications) {
    Block-Application -AppName $app.name -ProcessNames $app.processNames -Paths $app.paths
}

Write-Host "`n=== Done ===" -ForegroundColor Green
