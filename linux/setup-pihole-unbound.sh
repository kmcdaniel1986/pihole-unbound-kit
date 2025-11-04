#!/usr/bin/env bash
# One-shot installer: Pi-hole + Unbound with DNSSEC and local recursion

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y curl wget dnsutils unbound unbound-anchor

# Root hints & anchor
mkdir -p /var/lib/unbound
wget -O /var/lib/unbound/root.hints https://www.internic.net/domain/named.root
unbound-anchor -a /var/lib/unbound/root.key
chown unbound:unbound /var/lib/unbound/root.hints /var/lib/unbound/root.key
chmod 644 /var/lib/unbound/root.hints /var/lib/unbound/root.key

# Unbound config for Pi-hole (IPv4+IPv6)
cat >/etc/unbound/unbound.conf.d/pi-hole.conf <<'EOF'
server:
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    root-hints: "/var/lib/unbound/root.hints"
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    qname-minimisation: yes
    use-caps-for-id: yes
    edns-buffer-size: 1232
    prefetch: yes
EOF

systemctl enable --now unbound

# Pi-hole unattended (interactive if you want: remove --unattended)
if ! command -v pihole >/dev/null 2>&1; then
  curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended
fi

# Point Pi-hole to Unbound
sed -i 's/^PIHOLE_DNS_1=.*/PIHOLE_DNS_1=127.0.0.1#5335/' /etc/pihole/setupVars.conf || true
pihole restartdns || true

echo "Done. Verify: dig dnssec-failed.org @127.0.0.1 -p 5335 +dnssec (expect SERVFAIL)"
