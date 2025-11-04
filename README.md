# pihole-unbound-kit
A Pihole/Unbound kit that refreshes DNSSEC trust anchor on your Pi, restarts Unbound, all from your Windows PC

# Pi-hole + Unbound Kit (with Windows automation)

This repo contains:
- Windows automation to refresh Unbound's DNSSEC **trust anchor** monthly on a remote Pi (or VM)
- One-file installer for **Pi-hole + Unbound** (DNSSEC ready)
- Backup/restore **migration** script for Pi-hole + Unbound configs
- DNS leak test quick guide

## Prereqs

- On the Pi/VM (Debian/Ubuntu/Raspberry Pi OS):
  - `unbound`, `unbound-anchor`, `dnsutils`, `curl`, `wget`, `sudo`
  - Pi-hole installed (or install with `linux/setup-pihole-unbound.sh`)
- On Windows:
  - PowerShell 5+ (or 7+), built-in `ssh`
  - An SSH key placed in `~\.ssh\id_ed25519` (or change in the script)

## Sudo (optional but recommended)
Allow the remote user to run anchor + restart without password:

`sudo visudo` and add:
<USERNAME> ALL=(ALL) NOPASSWD:/usr/sbin/unbound-anchor, /bin/systemctl restart unbound

## Windows usage

1. Edit `windows/Update-UnboundTrustAnchor.ps1` and set:
   - `$PiUser` and `$PiHost` (IP or Tailscale IP)
2. Test:
  pwsh -File .\windows\Update-UnboundTrustAnchor.ps1
3. Register the monthly task:
  pwsh -File .\windows\Register-TrustAnchorTask.ps1
or import `TrustAnchorTask.xml` via Task Scheduler → Import Task.

## Linux quick install (VM)
On a fresh VM:
  sudo bash linux/setup-pihole-unbound.sh

## Migrate/Restore
On the source: `sudo bash linux/migrate/pihole-unbound-migrate.sh backup`  
On the target: `sudo bash linux/migrate/pihole-unbound-migrate.sh restore <archive.tar.gz>`

## DNS leak tests
See `tests/dns-leak-tests.md`.
