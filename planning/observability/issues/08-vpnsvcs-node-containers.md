# 08. Install Podman on the VPS and containerise node_exporter, fluent-bit and vmagent

Status: resolved
Type: task
Repo: homelab
Source: user item 50
Blocked by: 04, 11

## Decision (maintainer, 2026-09-27)

Podman goes on the VPS, for alignment with the other VMs: one install path, the same
secrets pipeline (`get_secret.sh`, SOPS), the same quadlet pattern, and the image
updater covering the VPS too.

Resource cost was checked and is small on a 1 vCPU / 1 GB Nanode:

| | Host packages | Podman quadlets |
|---|---|---|
| Idle RAM | node_exporter ~15 MB, fluent-bit ~20 MB | same, plus ~5–10 MB per container (conmon; netavark/aardvark are per network) ≈ +30 MB |
| Idle CPU | ~0 | ~0; no daemon |
| Disk | ~50 MB | Podman + netavark + crun ~150 MB, images ~200–250 MB ≈ 400 MB of 25 GB |
| Transient | apt upgrades | nightly image pulls: a few hundred MB and a brief CPU spike on the one core that also runs WireGuard |

HAProxy + Headscale + tailscaled (~150 MB) stay on the host. The real cost is surface,
not resources: netavark's nftables rules on the one public host, and Podman's own CVE
stream on the edge. Mitigations are in the prerequisites.

Scope of the first pass: `node_exporter`, `fluentbit`, `vmagent`. `geoip_generator`
stays a host unit until the Podman install is proven; containerising it is a follow-up
with no resource argument, only uniformity.

## Scope

Design from observability/04's Answer: every container uses `Network=host` and binds to
loopback, and vmagent pushes to secsvcs. Nothing new listens off `127.0.0.1`.

Quadlets under `src/vpnsvcs/`:

- `node_exporter` (reuse `src/node_exporter/`, textfile collector directory as on the
  other nodes): `--web.listen-address=127.0.0.1:9100`, `--pid=host`, `/` mounted at
  `/host:ro,rslave` with `--path.rootfs=/host`;
- `fluentbit` (journald → VictoriaLogs at `logs.SITE`; reuse `src/fluentbit/` with the
  VPS's unit list): `http_listen: 127.0.0.1`;
- `vmagent` (the shared template, with a `Network=host` branch and a `vpnsvcs)` case in
  `render_host.sh`): scrapes node_exporter, Headscale (`127.0.0.1:9090`), tailscaled
  (`100.100.100.100/metrics`) and fluent-bit, and remote-writes to `metrics.SITE` with
  `--remoteWrite.label=host=vpnsvcs.SITE`. The disk buffer from observability/11 covers
  tailnet and secsvcs outages.

Keep on the host: `haproxy` (needs the public IP and `chroot`), `headscale`, `tailscaled`,
`geoip_generator` (for now). HAProxy's own metrics are observability/12.

## Prerequisites

- `src/vpnsvcs/install_svcs.sh.j2` grows a `podman` case that installs Podman and copies
  `src/podman/*.sh` and `containers.conf`. No `net.network`: with host networking,
  netavark adds no nftables rules. Still compare `nft list ruleset` before and after.
- The telemetry names resolve to secsvcs through `/etc/hosts`, a manual step in
  `docs/guides/vpnsvcs.md.j2`.
- Secrets pipeline on the VPS (`/etc/opt/secrets/secrets.yaml.age`): check that
  `secret_update.sh vpnsvcs` already works there; add `victoriametrics_admin_password` for
  vmagent, the same credential the other vmagents use (maintainer decision 2026-09-27).
- The VPS joins the image-updater rollout (image-updater/05) so its images are scanned
  like the others.
- Alerts: `src/vmalert/configs/vps.yml` with `VpsMetricsAbsent`
  (`absent_over_time(up{job="node_exporter",host="vpnsvcs.SITE"}[5m])`). A pushing host can't raise `up == 0`,
  so exclude the VPS from observability/01's `NodeDown`.

## Acceptance

- `systemctl list-units '*.service' | grep Homelab` on the VPS shows the three services.
- `up{host="vpnsvcs.SITE"} == 1` for every scrape job; VPS journal lines appear in
  VictoriaLogs.
- `ss -ltnp` on the VPS shows no new listeners off loopback; an external port scan shows
  only 80, 443 and the Headscale/SSH ports it showed before.
- Stop tailscaled for 10 minutes and restart it: the VPS series have no gap.
- Idle RAM on the VPS grew by less than 100 MB.

## Follow-up

- Containerise `geoip_generator` as a `.container` + timer once the above has run for a
  few weeks.

## Comments

- 2026-09-26: triage questions added during ticket review.
- 2026-09-27 maintainer: Podman for alignment; resource delta (~30 MB RAM, ~400 MB disk)
  accepted. Marked ready-for-agent.
- 2026-09-27: rescoped to observability/04's Answer. HAProxy metrics are split out as
  observability/12, and the vmagent buffer fix as observability/11.
- 2026-09-27: observability/11 resolved. The shared vmagent template now sets
  `tmpDataPath=/vmagentdata` and `maxDiskUsagePerURL=1GiB`, so the VPS branch inherits
  them. Both blockers (04, 11) are resolved, so this ticket is unblocked. observability/12
  follows it.

- 2026-10-07: done. `install_podman` (Debian's podman, age/jq/yq/jinjanator, the shell
  secret driver, auto-update timer), then `node_exporter` (`src/vpnsvcs/node_exporter.container.j2`:
  host net + pid, `/` at `/host`, systemd collector over the mounted sockets, unit
  filter from the inventory), `fluentbit` and `vmagent` from the shared templates,
  which now branch on an empty `subnet` from `render_host.sh vpnsvcs` to
  `Network=host` and loopback listeners. `src/vpnsvcs/prometheus.yml.j2` scrapes the six
  jobs; `src/vpnsvcs/secrets_template.yaml` holds the two passwords for
  `secret_update.sh vpnsvcs`. `vps.yml` has `VpsMetricsAbsent`; `NodeDown` keeps the VPS
  (it fires if the node_exporter container dies under a live vmagent). ADR 0007.
  `geoip_generator` stays a host unit. Acceptance checks are in the apply note, step 9.
- 2026-10-10: networking revised (maintainer): the VPS now follows the Podman guide
  with its own `net.network` bridge (`vpnsvcs.container_subnet`), so the shared vmagent
  and Fluent Bit templates lose their `Network=host` branch, `render_host.sh vpnsvcs`
  hands them the subnet, and the VPS copies of the Fluent Bit config and the
  node_exporter quadlet are gone (node_exporter is the host binary, as on the VMs).
  HAProxy's exporter and Headscale's metrics bind the bridge gateway with
  `ip_nonlocal_bind`; ufw admits only `<subnet>.7`. The "nothing off loopback"
  acceptance becomes "nothing new reachable from outside" (an `nmap` from off the VPS).
  ADR 0007 updated.
- 2026-10-10: follow-up done. `geoip_generator` is a quadlet: `src/haproxy/geoip_generator.Containerfile`
  builds haproxy-mapper from source and adds the script, built on the VPS by
  `install_geoip_generator` (secsvcs's `build_haproxy_mapper` and the binary copy are
  gone). The license key is a podman secret from `vpnsvcs.yaml`; the container runs
  oneshot from the existing timer on the VPS's bridge (`.30`, the one IP ufw routes to
  the internet) and reloads HAProxy afterwards.
