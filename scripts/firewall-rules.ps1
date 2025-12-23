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

function Block-Application {
    param(
        [string]$AppName,
        [string[]]$ProcessNames,
        [string[]]$Paths
    )
    
    $ruleName = "ParentalControl-Block-$AppName"
    
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
    
    # Create rules for each process
    foreach ($processName in $ProcessNames) {
        try {
            # Block outbound traffic
            if ($config.blockAllMatching -or $config.blockOutbound) {
                New-NetFirewallRule -DisplayName "$ruleName-Out-$processName" `
                    -Direction Outbound `
                    -Program "*\$processName" `
                    -Action Block `
                    -Profile Any `
                    -Enabled True `
                    -ErrorAction Stop | Out-Null
                
                Write-Host "Created blocking rule: $AppName ($processName - Outbound)" -ForegroundColor Green
            }
            
            # Block inbound traffic (if enabled)
            if ($config.blockInbound) {
                New-NetFirewallRule -DisplayName "$ruleName-In-$processName" `
                    -Direction Inbound `
                    -Program "*\$processName" `
                    -Action Block `
                    -Profile Any `
                    -Enabled True `
                    -ErrorAction Stop | Out-Null
                
                Write-Host "Created blocking rule: $AppName ($processName - Inbound)" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "Error creating rule for $processName : $_"
        }
    }
    
    # Create rules for specific paths
    foreach ($path in $Paths) {
        # Expand environment variables
        $expandedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        
        # If path contains wildcard, use Get-ChildItem
        if ($expandedPath -match '\*') {
            $resolvedPaths = Get-ChildItem -Path $expandedPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            foreach ($resolvedPath in $resolvedPaths) {
                if (Test-Path $resolvedPath) {
                    try {
                        if ($config.blockOutbound -or $config.blockAllMatching) {
                            New-NetFirewallRule -DisplayName "$ruleName-Out-Path-$([System.IO.Path]::GetFileName($resolvedPath))" `
                                -Direction Outbound `
                                -Program $resolvedPath `
                                -Action Block `
                                -Profile Any `
                                -Enabled True `
                                -ErrorAction Stop | Out-Null
                        }
                        
                        if ($config.blockInbound) {
                            New-NetFirewallRule -DisplayName "$ruleName-In-Path-$([System.IO.Path]::GetFileName($resolvedPath))" `
                                -Direction Inbound `
                                -Program $resolvedPath `
                                -Action Block `
                                -Profile Any `
                                -Enabled True `
                                -ErrorAction Stop | Out-Null
                        }
                        
                        Write-Host "Created rule for path: $resolvedPath" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "Error creating rule for path $resolvedPath : $_"
                    }
                }
            }
        }
        else {
            if (Test-Path $expandedPath) {
                try {
                    if ($config.blockOutbound -or $config.blockAllMatching) {
                        New-NetFirewallRule -DisplayName "$ruleName-Out-Path-$([System.IO.Path]::GetFileName($expandedPath))" `
                            -Direction Outbound `
                            -Program $expandedPath `
                            -Action Block `
                            -Profile Any `
                            -Enabled True `
                            -ErrorAction Stop | Out-Null
                    }
                    
                    if ($config.blockInbound) {
                        New-NetFirewallRule -DisplayName "$ruleName-In-Path-$([System.IO.Path]::GetFileName($expandedPath))" `
                            -Direction Inbound `
                            -Program $expandedPath `
                            -Action Block `
                            -Profile Any `
                            -Enabled True `
                            -ErrorAction Stop | Out-Null
                    }
                    
                    Write-Host "Created rule for path: $expandedPath" -ForegroundColor Green
                }
                catch {
                    Write-Warning "Error creating rule for path $expandedPath : $_"
                }
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
