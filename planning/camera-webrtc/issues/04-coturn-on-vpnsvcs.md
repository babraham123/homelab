# 04. coturn on vpnsvcs

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-13

## Problem

Off-VPN clients can't reach `websvcs:8555`; nothing is port-forwarded at home. WebRTC
needs a relay on the one public machine.

## Change

- **`src/nodes/vpnsvcs/install_svcs.sh.j2`** `coturn` case: `apt install -y coturn`,
  `base/debian/add_homelab_tag.sh` on its unit, copy `services/coturn/turnserver.conf` to
  `/etc/turnserver.conf`, and fill the credential from
  `/etc/opt/secrets/coturn_webrtc_password` (host services keep plain files there). Add
  `coturn: {}` to `src/nodes/vpnsvcs/inventory.yml`.
- **`src/services/coturn/turnserver.conf.j2`:**

  ```ini
  listening-port=3479          # Headscale's DERP STUN holds UDP 3478
  # alt-listening-port defaults to listening-port+1, but RFC 5780 needs a 2nd IP; confirm nothing binds 3480
  no-tls
  no-dtls
  listening-ip={{ vpnsvcs.ip }}
  external-ip={{ vpnsvcs.ip }}
  min-port=49160
  max-port=49200               # ~20 concurrent sessions; widen if needed
  realm={{ site.url }}
  fingerprint
  lt-cred-mech
  user=webrtc:<coturn_webrtc_password>
  no-multicast-peers
  no-cli
  no-software-attribute
  # never relay into the tailnet or any private range
  denied-peer-ip=0.0.0.0-0.255.255.255
  denied-peer-ip=10.0.0.0-10.255.255.255
  denied-peer-ip=100.64.0.0-100.127.255.255
  denied-peer-ip=127.0.0.0-127.255.255.255
  denied-peer-ip=169.254.0.0-169.254.255.255
  denied-peer-ip=172.16.0.0-172.31.255.255
  denied-peer-ip=192.168.0.0-192.168.255.255
  denied-peer-ip=::1
  denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
  denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
  user-quota=4                 # concurrent allocations per user
  total-quota=20
  max-bps=1000000              # ~8 Mbit/s per session; above one 1080p stream
  bps-capacity=4000000
  log-file=syslog
  simple-log
  ```

  Static credential, not `use-auth-secret`: HA and go2rtc take a fixed
  username/credential (05). Verify every key against the installed version's
  `man turnserver`; `max-bps` semantics in particular (bytes vs bits).
- **ufw** (`src/nodes/vpnsvcs/install_firewall.sh.j2`):
  `ufw allow in 3479` (tcp+udp), `ufw allow in 49160:49200/udp`. Outbound is already
  allowed on `$NET_IFACE`.
- **Backup:** add `/etc/turnserver.conf` to `src/nodes/vpnsvcs/backup.sh.j2` and the
  `files/` list in `docs/guides/vpnsvcs.md.j2` "Backup and restore".
- **Docs:**
  - `docs/security.md` "VPS hardening": the new ports, and TURN's containment
    (denied peers, quotas, credential leak = transfer cost only);
  - `docs/services.md` vpnsvcs row; `docs/architecture.md` vpnsvcs paragraph;
  - an ADR at the next free number: "coturn on the VPS, relay-to-relay only".

## Acceptance

- `turnutils_uclient -u webrtc -w … -p 3479 {{ vpnsvcs.ip }}` from devtop allocates and
  relays.
- A TURN allocation asking for a permission to `{{ websvcs.ip }}` or a `100.64.x` address
  is refused (`403 Forbidden IP` in the log).
- Trickle ICE (webrtc.github.io/samples/src/content/peerconnection/trickle-ice) shows a
  `srflx` candidate from `stun:{{ vpnsvcs.ip }}:3479` and a `relay` candidate from
  `turn:{{ vpnsvcs.ip }}:3479`.
- `ss -lunp` shows 3478 still owned by Headscale; `tailscale netcheck` on a client still
  reports the home DERP region's STUN.
- Idle RAM on vpnsvcs grew by less than 30 MB.

## Follow-up

- TURNS on :443: HAProxy SNI-routes `turn.SITE` to coturn's TLS port, with a cert for
  `turn.SITE`. For hotel/corporate networks that block UDP.

## Comments
