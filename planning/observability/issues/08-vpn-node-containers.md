# 08. Install Podman on the VPS and containerise node_exporter, fluent-bit and vmagent

Status: ready-for-agent
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

Quadlets under `src/vpn/`:

- `node_exporter` (reuse `src/node_exporter/`, textfile collector directory as on the
  other nodes): `--web.listen-address=127.0.0.1:9100`, `--pid=host`, `/` mounted at
  `/host:ro,rslave` with `--path.rootfs=/host`;
- `fluentbit` (journald → VictoriaLogs at `logs.SITE`; reuse `src/fluentbit/` with the
  VPS's unit list): `http_listen: 127.0.0.1`;
- `vmagent` (the shared template, with a `Network=host` branch and a `vpn)` case in
  `render_host.sh`): scrapes node_exporter, Headscale (`127.0.0.1:9090`), tailscaled
  (`100.100.100.100/metrics`) and fluent-bit, and remote-writes to `metrics.SITE` with
  `--remoteWrite.label=host=vpn.SITE`. The disk buffer from observability/11 covers
  tailnet and secsvcs outages.

Keep on the host: `haproxy` (needs the public IP and `chroot`), `headscale`, `tailscaled`,
`geoip_generator` (for now). HAProxy's own metrics are observability/12.

## Prerequisites

- `src/vpn/install_svcs.sh.j2` grows a `podman` case that installs Podman and copies
  `src/podman/*.sh` and `containers.conf`. No `net.network`: with host networking,
  netavark adds no nftables rules. Still compare `nft list ruleset` before and after.
- The telemetry names resolve to secsvcs through `/etc/hosts`, a manual step in
  `docs/guides/vpn.md.j2`.
- Secrets pipeline on the VPS (`/etc/opt/secrets/secrets.yaml.age`): check that
  `secret_update.sh vpn` already works there; add `victoriametrics_admin_password` for
  vmagent, the same credential the other vmagents use (maintainer decision 2026-09-27).
- The VPS joins the image-updater rollout (image-updater/05) so its images are scanned
  like the others.
- Alerts: `src/vmalert/configs/vps.yml` with `VpsMetricsAbsent`
  (`absent_over_time(up{job="node_exporter",host="vpn.SITE"}[5m])`). A pushing host can't raise `up == 0`,
  so exclude the VPS from observability/01's `NodeDown`.

## Acceptance

- `systemctl list-units '*.service' | grep Homelab` on the VPS shows the three services.
- `up{host="vpn.SITE"} == 1` for every scrape job; VPS journal lines appear in
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

2026-09-28 (restructure/08): the vpn node is now `vpnsvcs`: `src/vpnsvcs/`, `vpnsvcs.ip`, host `vpnsvcs.SITE`, guide `docs/guides/vpnsvcs.md.j2`, archives `vpnsvcs-full-*`. `vpn.SITE` stays the Headscale endpoint. Use the new names where this ticket says vpn; see phase 8 of `planning/restructure/vpn-rename-runbook.md`.
