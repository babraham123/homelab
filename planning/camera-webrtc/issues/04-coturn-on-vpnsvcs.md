# 04. coturn on vpnsvcs

Status: wontfix
Type: task
Repo: homelab
Source: maintainer request 2026-10-13; hardening review 2026-10-16

## Problem

Off-VPN clients can't reach `websvcs:8555`; nothing is port-forwarded at home. WebRTC
needs a relay on the one public machine. It's the only service on vpnsvcs that relays
arbitrary UDP for authenticated strangers, so it has to be locked down harder than the
rest.

## Why a container

Debian trixie ships coturn 4.6.1-2 with 19 open CVEs and no DSA. They include three
`denied-peer-ip` bypasses (IPv4-mapped `::ffff:` peers, CVE-2026-27624; NAT64/6to4/
IPv4-compatible forms over TCP CONNECT, CVE-2026-73212; non-prefix-aligned IPv6 ranges,
CVE-2026-73213), a pre-auth heap disclosure (ACME redirect) and a MOBILITY allocation
takeover. forky/sid have 4.18.0; there's no trixie backport.

So coturn runs from the project's `coturn/coturn` image (Debian trixie base, `USER
nobody`) as a Quadlet on vpnsvcs's host network. It's still on the host in every sense
that mattered for the 2026-10-13 decision (same box, real public IP, no NAT), and it
picks up the scan gate and auto-updates from `base/podman/image_updater.py`
(ADR 0008). Revisit when trixie gets a fixed package.

## Change

- **Inventory** (`src/nodes/vpnsvcs/inventory.yml`):
  `coturn: {upstream: docker.io/coturn/coturn:4.18-trixie}` under the quadlets.
- **`src/services/coturn/coturn.container.j2`**, following `fluentbit.container`:
  - `Image=localhost/coturn/coturn:4.18-trixie`, `ContainerName=coturn`,
    `AutoUpdate=local`;
  - `Network=host`: the relay range and the real source addresses don't survive the
    podman bridge;
  - `NoNewPrivileges=true`, `DropCapability=all` (every port is above 1024),
    `ReadOnly=true`, `User=65534:65534`;
  - a memory cap (`PodmanArgs=--memory=64m --pids-limit=64`) so a flood can't take the
    VPS down with it;
  - `Volume=/etc/opt/coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro`;
  - `Exec=-c /etc/coturn/turnserver.conf`. Check the image's `docker-entrypoint.sh`:
    its default CMD adds `--external-ip=$(detect-external-ip)`, which a fixed `Exec`
    replaces.
- **`src/nodes/vpnsvcs/install_svcs.sh.j2`** `coturn` case: render the conf to
  `/etc/opt/coturn/turnserver.conf`, fill the credential from
  `/etc/opt/secrets/coturn_viewer_password` with `sed`, as the CrowdSec bouncer case
  does (`die` if empty), `install -m 600 -o 65534 -g 65534`; then `install_quadlet`
  and `reload_restart coturn`. The password never goes on a command line or into
  `rendered/`. Add the file to the comment in `src/nodes/vpnsvcs/secrets_template.yaml`.
- **`src/services/coturn/turnserver.conf.j2`** (4.18 syntax):

  ```ini
  listening-port=3479          # Headscale's DERP STUN holds UDP 3478
  listening-ip={{ vpnsvcs.ip }}
  relay-ip={{ vpnsvcs.ip }}    # IPv4 only: no IPv6 relays at all
  external-ip={{ vpnsvcs.ip }}
  min-port=49160
  max-port=49200               # ~20 concurrent sessions; widen if needed
  no-tls                       # TURNS is a follow-up; DTLS is off unless `dtls` is set
  no-tcp-relay                 # WebRTC only uses UDP relays; TCP relay was the CVE-2026-73212 path
  realm={{ site.url }}
  fingerprint
  lt-cred-mech
  user=viewer:<coturn_viewer_password>
  no-multicast-peers
  unauthorized-ratelimit       # experimental (4.14+), UDP 401s only

  # Never relay to vpnsvcs itself: traffic to its own IP goes over lo, which ufw
  # accepts, so Headscale :8443, DERP STUN, tailscaled and coturn would all be reachable.
  denied-peer-ip={{ vpnsvcs.ip }}
  # Never relay into the tailnet or any private or special-purpose range. 4.13.1+ denies
  # link-local and ULA itself; they stay listed in case of a downgrade.
  denied-peer-ip=0.0.0.0-0.255.255.255
  denied-peer-ip=10.0.0.0-10.255.255.255
  denied-peer-ip=100.64.0.0-100.127.255.255
  denied-peer-ip=127.0.0.0-127.255.255.255
  denied-peer-ip=169.254.0.0-169.254.255.255
  denied-peer-ip=172.16.0.0-172.31.255.255
  denied-peer-ip=192.0.0.0-192.0.0.255
  denied-peer-ip=192.0.2.0-192.0.2.255
  denied-peer-ip=192.88.99.0-192.88.99.255
  denied-peer-ip=192.168.0.0-192.168.255.255
  denied-peer-ip=198.18.0.0-198.19.255.255
  denied-peer-ip=198.51.100.0-198.51.100.255
  denied-peer-ip=203.0.113.0-203.0.113.255
  denied-peer-ip=224.0.0.0-255.255.255.255
  denied-peer-ip=::1
  denied-peer-ip=::ffff:0.0.0.0-::ffff:255.255.255.255
  denied-peer-ip=64:ff9b::-64:ff9b::ffff:ffff
  denied-peer-ip=64:ff9b:1::-64:ff9b:1:ffff:ffff:ffff:ffff:ffff
  denied-peer-ip=100::-100::ffff:ffff:ffff:ffff
  denied-peer-ip=2001::-2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff
  denied-peer-ip=2001:db8::-2001:db8:ffff:ffff:ffff:ffff:ffff:ffff
  denied-peer-ip=2002::-2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff
  denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
  denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff

  user-quota=6                 # one browser allocates per local interface
  total-quota=20
  max-bps=1000000              # bytes/s: ~8 Mbit/s per session, above one 1080p stream
  bps-capacity=4000000
  log-file=stdout              # journald → fluent-bit → VictoriaLogs
  ```

  Don't add `no-cli`, `no-dtls` or `drop-invalid-packets`: 4.18 removed them (CLI and
  DTLS are off by default). `no-rfc5780`, `no-software-attribute` and
  `no-stun-backward-compatibility` are already the defaults. Never set `mobility`,
  `server-relay`, `allow-loopback-peers` or `no-auth`. Never write
  `denied-peer-ip=::0`: coturn reads it as a wildcard. Confirm `no-tls` and
  `unauthorized-ratelimit` are still accepted (`turnserver --help` in the image).
- **One TURN user, for browsers only.** go2rtc gets STUN only (03), so coturn never
  relays to its own address and no credential lives on websvcs. HA hands `viewer` to
  every logged-in HA user (05) and only takes static credentials, so it's
  rotate-on-leak: change the file, rerun the case, update HA's secret.
- **ufw** (`src/nodes/vpnsvcs/install_firewall.sh.j2`):
  `ufw allow in 3479` (tcp+udp), `ufw allow in 49160:49200/udp`. Outbound is already
  allowed on `$NET_IFACE`. Update the header comment and `docs/security.md`'s port list.
- **Per-source rate limit.** In the `coturn` case, an nftables table
  `inet homelab_turn` (separate from ufw's, like 06's `homelab_acct`) with an input
  hook that drops more than ~20 new 3479 flows/s per source address (a dynamic set
  with a timeout). The relay range needs none: coturn drops packets from peers without
  a permission.
- **Backup:** add `/etc/opt/coturn/turnserver.conf` to `src/nodes/vpnsvcs/backup.sh.j2`
  and the `files/` list in `docs/guides/vpnsvcs.md.j2` "Backup and restore".
- **Docs:**
  - `docs/security.md` "VPS hardening": the new ports, and TURN's containment:
    - denied peers, including vpnsvcs itself;
    - UDP relay only;
    - quotas and the rate limit;
    - a leaked credential costs transfer only.
  - `docs/services.md` vpnsvcs row; `docs/architecture.md` vpnsvcs paragraph.
  - An ADR at the next free number: "coturn on the VPS: browser relay only, from the
    upstream image".

## Acceptance

- `turnutils_uclient -u viewer -w … -p 3479 {{ vpnsvcs.ip }}` from devtop allocates and
  relays.
- A permission or channel-bind for each of these peers is refused (`403` in the log):
  `{{ websvcs.ip }}`, a `100.64.x` address, `{{ vpnsvcs.ip }}`, `::ffff:127.0.0.1`,
  `64:ff9b::7f00:1`. `turnutils_uclient -e <peer>` does this.
- A TCP allocation (`turnutils_uclient -T`) is refused.
- Trickle ICE (webrtc.github.io/samples/src/content/peerconnection/trickle-ice) with
  only `turn:{{ vpnsvcs.ip }}:3479` listed shows both a `srflx` and a `relay` candidate.
  Chrome uses UDP TURN servers for STUN too.
- `ss -lunp` shows 3478 still owned by Headscale, 3479 by coturn, and nothing on 3480.
  `tailscale netcheck` on a client still reports the home DERP region's STUN.
- `podman inspect coturn` shows user 65534, no capabilities and a read-only rootfs.
- A burst of 100 STUN binding requests from one address, each from a new source port,
  is cut off by the rate limit
  (`nft list set inet homelab_turn …` shows the source).
- Idle RAM on vpnsvcs grew by less than 30 MB.

## Follow-up

- TURNS on :443: HAProxy SNI-routes `turn.SITE` to coturn's TLS port, with a cert for
  `turn.SITE`. For hotel/corporate networks that block UDP. Needs `dtls`/TLS options in
  4.18 syntax.
- coturn's Prometheus exporter, bound to `{{ vpnsvcs.container_subnet }}.1` and pushed by
  vmagent, if the upstream image is built with it (its Dockerfile doesn't list libprom).
- A fail2ban jail on bad-credential log lines, if abuse shows up. The first 401 of every
  allocation is a normal challenge, so the filter can't match bare 401s.

## Comments

2026-10-16, hardening review: switched from the trixie package to the upstream image
(open CVEs), browser-only credential `viewer` replaces the shared `webrtc` user, go2rtc no
longer allocates (Frigate's `/api/config` exposed its TURN credential to every Frigate
user, and relay-to-relay required coturn to relay to its own IP), added `no-tcp-relay`,
`relay-ip`, the self/IPv6-wrapper denies, container sandboxing and a per-source rate
limit. Sources: Debian security tracker (coturn), coturn GitHub advisories and ChangeLog,
Enable Security's coturn configuration guide.

2026-10-16, closed as wontfix for security reasons. Even with the hardening above, TURN
puts a second pre-auth C parser on the public internet (coturn had 19 CVEs in 2026,
including a pre-auth heap disclosure and three `denied-peer-ip` bypasses), and the
`viewer` credential goes to every logged-in HA user, so a leak turns vpnsvcs into an
open UDP relay: abuse reports, IP reputation, up to ~10 TB/month of egress at
`bps-capacity=4000000`. With host networking, a compromised coturn also shares vpnsvcs's
network namespace and tailnet reach. Off-VPN viewing falls back to MSE over HTTPS through
the existing ingress, at higher latency. The config above stays as the starting point if
this is reopened.
