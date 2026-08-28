# =============================================================
# install-cronjob-windows.ps1
#   One-click registration of the collector / push scripts as Windows scheduled tasks
#
# Creates two tasks:
#   RouterMetrics-Collect  writes metrics every 1 minute by default
#   RouterMetrics-Push     commits and pushes accumulated data every hour
#
# Usage (in the repo root, from an elevated PowerShell):
#   powershell -ExecutionPolicy Bypass -File init\install-cronjob-windows.ps1
#
# Customize collection frequency:
#   powershell -ExecutionPolicy Bypass -File init\install-cronjob-windows.ps1 `
#       -CollectMinutes 1
#
# To uninstall, run: init\uninstall-cronjob-windows.ps1
# =============================================================

param(
    [ValidateRange(1, 59)]
    [int]$CollectMinutes = 1
)

$ErrorActionPreference = 'Stop'

$RepoDir   = Split-Path -Parent $PSScriptRoot
$CollectJs = Join-Path $RepoDir 'scripts\router-metrics-collect.js'
$PushJs    = Join-Path $RepoDir 'scripts\git-push.js'

$TaskCollect = 'RouterMetrics-Collect'
$TaskPush    = 'RouterMetrics-Push'

# ---- Pre-flight checks ----
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw "node not found; please install Node.js first (https://nodejs.org)." }
if (-not (Test-Path $CollectJs)) { throw "Cannot find $CollectJs" }
if (-not (Test-Path $PushJs))    { throw "Cannot find $PushJs" }
if (-not (Test-Path (Join-Path $RepoDir '.env'))) {
    Write-Host "Warning: no .env found; please copy .env.example to .env and fill in the config first." -ForegroundColor Yellow
}

Write-Host "Node:  $node"
Write-Host "Repo:  $RepoDir"
Write-Host ""

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

function Remove-IfExists($name) {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
        Write-Host "Already exists, recreating: $name"
    }
}

# ---- Collection task: every N minutes ----
Remove-IfExists $TaskCollect
$collectAction  = New-ScheduledTaskAction -Execute $node -Argument "`"$CollectJs`"" -WorkingDirectory $RepoDir
$collectTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $CollectMinutes)
Register-ScheduledTask -TaskName $TaskCollect -Action $collectAction -Trigger $collectTrigger `
    -Principal $principal -Settings $settings `
    -Description "Router metrics collection (write data every ${CollectMinutes} min)" | Out-Null
Write-Host "Created: $TaskCollect (every $CollectMinutes min)" -ForegroundColor Green

# ---- Commit and push task: at the start of every hour ----
Remove-IfExists $TaskPush
$pushAction  = New-ScheduledTaskAction -Execute $node -Argument "`"$PushJs`"" -WorkingDirectory $RepoDir
$nextHour = (Get-Date).Date.AddHours((Get-Date).Hour + 1)
$pushTrigger = New-ScheduledTaskTrigger -Once -At $nextHour `
    -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName $TaskPush -Action $pushAction -Trigger $pushTrigger `
    -Principal $principal -Settings $settings `
    -Description "Router metrics hourly commit and push" | Out-Null
Write-Host "Created: $TaskPush (hourly, next run at $nextHour)" -ForegroundColor Green

Write-Host ""
Write-Host "Done! Check it in Task Scheduler, or test immediately:" -ForegroundColor Green
Write-Host "  Start-ScheduledTask -TaskName $TaskCollect"
Write-Host "  Get-ScheduledTask -TaskName $TaskCollect | Get-ScheduledTaskInfo"
Write-Host ""
Write-Host "Log files: $RepoDir\logs\collect.log and $RepoDir\logs\push.log"
Write-Host "Uninstall: powershell -ExecutionPolicy Bypass -File init\uninstall-cronjob-windows.ps1"
