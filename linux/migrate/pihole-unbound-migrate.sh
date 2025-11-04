#!/usr/bin/env bash
# pihole-unbound-migrate.sh
# Backup & restore Pi-hole + Unbound configuration (Pi → VM or VM → VM)
# Usage:
#   sudo ./pihole-unbound-migrate.sh backup
#   sudo ./pihole-unbound-migrate.sh restore /path/to/backup.tar.gz

set -euo pipefail

RED()  { printf "\033[31m%s\033[0m\n" "$*" ; }
GRN()  { printf "\033[32m%s\033[0m\n" "$*" ; }
YEL()  { printf "\033[33m%s\033[0m\n" "$*" ; }
BLU()  { printf "\033[34m%s\033[0m\n" "$*" ; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    RED "Please run as root (use sudo)."; exit 1
  fi
}

check_cmds() {
  local missing=0
  for c in tar gzip awk sed date hostname; do
    command -v "$c" >/dev/null 2>&1 || { RED "Missing: $c"; missing=1; }
  done
  [[ $missing -eq 0 ]] || { RED "Install missing tools and re-run."; exit 1; }
}

timestamp() { date +"%Y%m%d_%H%M%S"; }

backup() {
  need_root; check_cmds
  local host; host=$(hostname -s)
  local ts; ts=$(timestamp)
  local out="pihole_unbound_backup_${host}_${ts}.tar.gz"

  # Collect versions (best-effort)
  local PH_VER UNB_VER
  PH_VER="$(pihole -v 2>/dev/null || true)"
  UNB_VER="$(unbound -V 2>/dev/null | head -n1 || true)"

  # Build a temp staging dir
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/backup"
  YEL "Staging files under: $tmp"

  # What we back up:
  # - Pi-hole config & db
  # - dnsmasq includes used by Pi-hole
  # - Unbound configs + trust anchor + root hints
  # - Monthly cron for unbound-anchor (if present)
  # - A small info file with host + versions

  # Pi-hole (if installed)
  if [[ -d /etc/pihole ]]; then
    cp -a /etc/pihole "$tmp/backup/"
  fi

  # dnsmasq includes (Pi-hole uses /etc/dnsmasq.d/*.conf)
  if [[ -d /etc/dnsmasq.d ]]; then
    cp -a /etc/dnsmasq.d "$tmp/backup/"
  fi

  # Unbound configs
  if [[ -d /etc/unbound ]]; then
    mkdir -p "$tmp/backup/etc-unbound"
    cp -a /etc/unbound/unbound.conf* "$tmp/backup/etc-unbound/" 2>/dev/null || true
    if [[ -d /etc/unbound/unbound.conf.d ]]; then
      cp -a /etc/unbound/unbound.conf.d "$tmp/backup/etc-unbound/" 2>/dev/null || true
    fi
  fi

  # Unbound state (trust anchor + root hints)
  if [[ -d /var/lib/unbound ]]; then
    mkdir -p "$tmp/backup/var-lib-unbound"
    cp -a /var/lib/unbound/root.key "$tmp/backup/var-lib-unbound/" 2>/dev/null || true
    cp -a /var/lib/unbound/root.hints "$tmp/backup/var-lib-unbound/" 2>/dev/null || true
  fi

  # Cron for trust anchor (if any)
  if [[ -f /etc/cron.monthly/unbound-anchor-update ]]; then
    mkdir -p "$tmp/backup/cron.monthly"
    cp -a /etc/cron.monthly/unbound-anchor-update "$tmp/backup/cron.monthly/"
  fi

  # Info file
  cat > "$tmp/backup/backup-info.json" <<EOF
{
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "created_at": "$(date -Iseconds)",
  "pihole_version": $(printf %q "$PH_VER"),
  "unbound_version": $(printf %q "$UNB_VER")
}
EOF

  # Create the archive
  (cd "$tmp" && tar -czf "$out" backup)
  mv "$tmp/$out" "./$out"
  rm -rf "$tmp"

  GRN "Backup created: ./$out"
  YEL "Contents: /etc/pihole, /etc/dnsmasq.d, /etc/unbound*, /var/lib/unbound/{root.key,root.hints}, monthly cron (if present)"
}

restore() {
  need_root; check_cmds
  local archive="${1:-}"
  [[ -f "$archive" ]] || { RED "Archive not found: $archive"; exit 1; }

  YEL "This will restore Pi-hole & Unbound configs over this system."
  YEL "Ensure you've installed base packages before restoring:"
  echo "    sudo apt update && sudo apt install -y unbound unbound-anchor dnsutils curl wget"
  echo "    (Install Pi-hole after restore, or beforehand, per your preference.)"
  read -rp "Proceed with restore? [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { RED "Aborted."; exit 1; }

  # Unpack to temp
  local tmp
  tmp="$(mktemp -d)"
  tar -xzf "$archive" -C "$tmp"
  [[ -d "$tmp/backup" ]] || { RED "Invalid archive format."; exit 1; }

  # Stop services during restore (best-effort)
  systemctl stop pihole-FTL 2>/dev/null || true
  systemctl stop unbound 2>/dev/null || true
  systemctl stop dnsmasq 2>/dev/null || true

  # Restore Pi-hole
  if [[ -d "$tmp/backup/pihole" ]]; then
    mkdir -p /etc
    cp -a "$tmp/backup/pihole" /etc/
  elif [[ -d "$tmp/backup/etc/pihole" ]]; then
    mkdir -p /etc
    cp -a "$tmp/backup/etc/pihole" /etc/
  fi

  # Restore dnsmasq includes
  if [[ -d "$tmp/backup/dnsmasq.d" ]]; then
    mkdir -p /etc
    cp -a "$tmp/backup/dnsmasq.d" /etc/
  elif [[ -d "$tmp/backup/etc/dnsmasq.d" ]]; then
    mkdir -p /etc
    cp -a "$tmp/backup/etc/dnsmasq.d" /etc/
  fi

  # Restore Unbound configs
  if [[ -d "$tmp/backup/etc-unbound" ]]; then
    mkdir -p /etc/unbound
    cp -a "$tmp/backup/etc-unbound/"* /etc/unbound/
  elif [[ -d "$tmp/backup/etc/unbound" ]]; then
    mkdir -p /etc/unbound
    cp -a "$tmp/backup/etc/unbound/"* /etc/unbound/
  fi

  # Restore Unbound state
  if [[ -d "$tmp/backup/var-lib-unbound" ]]; then
    mkdir -p /var/lib/unbound
    cp -a "$tmp/backup/var-lib-unbound/root.key" /var/lib/unbound/ 2>/dev/null || true
    cp -a "$tmp/backup/var-lib-unbound/root.hints" /var/lib/unbound/ 2>/dev/null || true
    chown unbound:unbound /var/lib/unbound/root.key 2>/dev/null || true
    chown unbound:unbound /var/lib/unbound/root.hints 2>/dev/null || true
    chmod 644 /var/lib/unbound/root.key 2>/dev/null || true
    chmod 644 /var/lib/unbound/root.hints 2>/dev/null || true
  fi

  # Restore cron (if present)
  if [[ -f "$tmp/backup/cron.monthly/unbound-anchor-update" ]]; then
    cp -a "$tmp/backup/cron.monthly/unbound-anchor-update" /etc/cron.monthly/
    chmod +x /etc/cron.monthly/unbound-anchor-update
  fi

  # Ensure root.hints exists (refresh if missing)
  if [[ ! -f /var/lib/unbound/root.hints ]]; then
    mkdir -p /var/lib/unbound
    wget -O /var/lib/unbound/root.hints https://www.internic.net/domain/named.root || true
    chown unbound:unbound /var/lib/unbound/root.hints 2>/dev/null || true
    chmod 644 /var/lib/unbound/root.hints 2>/dev/null || true
  fi

  # Ensure trust anchor exists (refresh if missing)
  if [[ ! -f /var/lib/unbound/root.key ]]; then
    unbound-anchor -a /var/lib/unbound/root.key || true
    chown unbound:unbound /var/lib/unbound/root.key 2>/dev/null || true
    chmod 644 /var/lib/unbound/root.key 2>/dev/null || true
  fi

  # Validate Unbound config (won't start if invalid)
  if command -v unbound-checkconf >/dev/null 2>&1; then
    unbound-checkconf
  fi

  # Start services (best-effort)
  systemctl enable --now unbound 2>/dev/null || true
  systemctl restart unbound 2>/dev/null || true

  # If Pi-hole is installed, point it to Unbound and rebuild gravity
  if command -v pihole >/dev/null 2>&1; then
    sed -i 's/^PIHOLE_DNS_1=.*/PIHOLE_DNS_1=127.0.0.1#5335/' /etc/pihole/setupVars.conf || true
    pihole restartdns || true
    pihole -g || true
    systemctl enable --now pihole-FTL 2>/dev/null || true
    systemctl restart pihole-FTL 2>/dev/null || true
  fi

  rm -rf "$tmp"

  GRN "Restore complete."
  YEL "If this host/VM uses a different IP than your Pi, update your router's DNS or DHCP static maps accordingly."
  BLU "Verification examples:"
  echo "  dig sigok.verteiltesysteme.net @127.0.0.1 -p 5335 +dnssec | grep flags  # expect: ad"
  echo "  dig dnssec-failed.org @127.0.0.1 -p 5335 +dnssec                        # expect: SERVFAIL"
  echo "  dig google.com @127.0.0.1 | grep SERVER                                 # expect: 127.0.0.1#53"
}

main() {
  case "${1:-}" in
    backup)  backup ;;
    restore) restore "${2:-}";;
    *) YEL "Usage: sudo $0 backup | restore <backup.tar.gz>"; exit 1 ;;
  esac
}

main "$@"
