# Check Parental Control Status
# Run to see what is installed and active

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Parental Control Status Check" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. AdGuard Home
Write-Host "[1] AdGuard Home:" -ForegroundColor Yellow

$adguardService = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
if ($adguardService) {
    Write-Host "  Type: Windows Service" -ForegroundColor White
    Write-Host "  Status: $($adguardService.Status)" -ForegroundColor $(if ($adguardService.Status -eq 'Running') { 'Green' } else { 'Red' })
} else {
    $dockerContainer = docker ps --filter "name=adguard" --format "{{.Names}}: {{.Status}}" 2>$null
    if ($dockerContainer) {
        Write-Host "  Type: Docker Container" -ForegroundColor White
        Write-Host "  Status: $dockerContainer" -ForegroundColor Green
    } else {
        Write-Host "  Not installed" -ForegroundColor Gray
    }
}

# 2. Scheduled Tasks
Write-Host "`n[2] Scheduled Tasks:" -ForegroundColor Yellow

$tasks = Get-ScheduledTask -TaskName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($tasks) {
    foreach ($task in $tasks) {
        $state = $task.State
        $color = switch ($state) {
            "Ready" { "Green" }
            "Running" { "Cyan" }
            "Disabled" { "Yellow" }
            default { "White" }
        }
        Write-Host "  $($task.TaskName): $state" -ForegroundColor $color
    }
} else {
    Write-Host "  No tasks found" -ForegroundColor Gray
}

# 3. Firewall Rules
Write-Host "`n[3] Firewall Rules:" -ForegroundColor Yellow

$rules = Get-NetFirewallRule -DisplayName "ParentalControl-*" -ErrorAction SilentlyContinue
if ($rules) {
    $ruleCount = ($rules | Measure-Object).Count
    $enabledCount = ($rules | Where-Object { $_.Enabled -eq $true } | Measure-Object).Count
    Write-Host "  Total rules: $ruleCount" -ForegroundColor White
    Write-Host "  Enabled: $enabledCount" -ForegroundColor $(if ($enabledCount -gt 0) { 'Green' } else { 'Yellow' })
    
    # Group by app
    $rulesByApp = $rules | Group-Object { $_.DisplayName -replace '-Out-.*|-In-.*', '' }
    foreach ($group in $rulesByApp) {
        Write-Host "    $($group.Name): $($group.Count) rules" -ForegroundColor Gray
    }
} else {
    Write-Host "  No rules found" -ForegroundColor Gray
}

# 4. DNS Settings
Write-Host "`n[4] DNS Settings:" -ForegroundColor Yellow

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($adapter in $adapters) {
    $dns = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $dnsServers = $dns.ServerAddresses -join ", "
    if ($dnsServers -eq "") { $dnsServers = "(DHCP)" }
    
    $isLocalDns = $dnsServers -match "127\.0\.0\.1"
    $color = if ($isLocalDns) { "Green" } else { "Yellow" }
    
    Write-Host "  $($adapter.Name): $dnsServers" -ForegroundColor $color
}

# 5. Excluded Users
Write-Host "`n[5] Configuration:" -ForegroundColor Yellow

$configPath = "$PSScriptRoot\..\config\time-limits.json"
if (Test-Path $configPath) {
    $config = Get-Content $configPath | ConvertFrom-Json
    
    if ($config.excludedUsers) {
        Write-Host "  Excluded users: $($config.excludedUsers -join ', ')" -ForegroundColor Green
    }
    
    if ($config.dailyLimit.enabled) {
        Write-Host "  Daily limit: $($config.dailyLimit.hours) hours" -ForegroundColor White
    }
    
    if ($config.nightShutdown.enabled) {
        Write-Host "  Night shutdown: $($config.nightShutdown.startTime) - $($config.nightShutdown.endTime)" -ForegroundColor White
    }
    
    if ($config.schedule.enabled) {
        Write-Host "  Schedule: Enabled" -ForegroundColor White
    }
} else {
    Write-Host "  Config not found" -ForegroundColor Gray
}

# 6. Current logged in users
Write-Host "`n[6] Logged in users:" -ForegroundColor Yellow

$users = quser 2>$null
if ($users) {
    foreach ($line in $users) {
        if ($line -notmatch "USERNAME") {
            Write-Host "  $line" -ForegroundColor White
        }
    }
} else {
    Write-Host "  No users or quser not available" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Commands" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nTo remove all parental control:" -ForegroundColor Yellow
Write-Host "  .\scripts\remove-parental-control.ps1" -ForegroundColor White

Write-Host "`nTo disable Scheduled Tasks temporarily:" -ForegroundColor Yellow
Write-Host "  Get-ScheduledTask -TaskName 'ParentalControl-*' | Disable-ScheduledTask" -ForegroundColor White

Write-Host "`nTo enable Scheduled Tasks:" -ForegroundColor Yellow
Write-Host "  Get-ScheduledTask -TaskName 'ParentalControl-*' | Enable-ScheduledTask" -ForegroundColor White

Write-Host ""

