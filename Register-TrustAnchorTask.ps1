<#
.SYNOPSIS
  Create/Update a monthly Scheduled Task to refresh Unbound trust anchor on the Pi.

.DESCRIPTION
  Uses the Update-UnboundTrustAnchor.ps1 script. Sets a Monthly trigger on day 1 at 03:10.
#>

param(
  [string]$ScriptPath = "$PSScriptRoot\Update-UnboundTrustAnchor.ps1",
  [string]$TaskName = "Update Unbound Trust Anchor (Pi-hole)",
  [int]$Day = 1,
  [string]$Time = "03:10"
)

$Action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
$Trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth $Day -At (Get-Date $Time)

# Run as current user, with highest privs
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest

$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries)

Register-ScheduledTask -TaskName $TaskName -InputObject $Task -Force | Out-Null
Write-Host "✓ Scheduled Task '$TaskName' created/updated." -ForegroundColor Green
