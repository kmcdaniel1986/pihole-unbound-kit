<#
.SYNOPSIS
  Refresh Unbound DNSSEC trust anchor on a remote Pi/VM and restart Unbound.

.DESCRIPTION
  Runs unbound-anchor on the remote host and restarts unbound.
  Works great over Tailscale (use 100.x.y.z for $PiHost).

.NOTES
  Requires passwordless sudo for:
    /usr/sbin/unbound-anchor
    /bin/systemctl restart unbound
  or adjust to use a password prompt.
#>

param(
  [string]$PiUser = "pi",
  [string]$PiHost = "100.100.100.100", # set to your Pi/VM or Tailscale IP
  [string]$KeyPath = "$HOME\.ssh\id_ed25519",
  [string]$AnchorFile = "/var/lib/unbound/root.key",
  [string]$HintsFile  = "/var/lib/unbound/root.hints"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  throw "OpenSSH client not found. Install 'OpenSSH Client' feature in Windows."
}
if (-not (Test-Path $KeyPath)) {
  Write-Warning "SSH key not found at $KeyPath. The command may prompt for a password."
}

$Remote = "$PiUser@$PiHost"

# The remote command; -F forces update if needed
$Cmd = @"
sudo /usr/sbin/unbound-anchor -a $AnchorFile -r $HintsFile -F
sudo /bin/systemctl restart unbound
"@

# Normalize line endings and run
$OneLine = ($Cmd -replace "`r","" -replace "`n"," ; ").Trim()

# Use explicit key if present
$sshArgs = @()
if (Test-Path $KeyPath) { $sshArgs += @("-i", $KeyPath) }
$sshArgs += @($Remote, $OneLine)

$LASTEXITCODE = 0
& ssh @sshArgs
if ($LASTEXITCODE -ne 0) {
  throw "Remote command failed with exit code $LASTEXITCODE"
}

Write-Host "✓ Unbound trust anchor updated and Unbound restarted on $PiHost." -ForegroundColor Green
