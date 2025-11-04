# DNS Leak Tests (Pi-hole + Unbound)

## Browser-based
- https://www.dnsleaktest.com/ → run “Extended Test”
  - Expect NOT to see Google (8.8.8.8), Cloudflare (1.1.1.1), or OpenDNS.
- https://browserleaks.com/dns → see resolvers used by the browser

## Command-line
From any client using Pi-hole:
```bash
dig cloudflare.com +dnssec | grep flags     # expect 'ad' in flags
dig dnssec-failed.org +dnssec               # expect SERVFAIL
dig google.com @<PIHOLE_IP> | grep SERVER   # expect PIHOLE_IP#53
