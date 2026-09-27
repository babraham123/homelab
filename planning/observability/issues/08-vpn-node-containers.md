# 08. Install Podman on the VPS and containerise node_exporter, fluent-bit and vmagent

Status: ready-for-agent
Type: task
Repo: homelab
Source: user item 50
Blocked by: 04

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

Quadlets under `src/vpn/`:

- `node_exporter` (reuse `src/node_exporter/`, textfile collector directory as on the
  other nodes);
- `fluentbit` (journald → VictoriaLogs over the tailnet; reuse `src/fluentbit/` with the
  VPS's unit list);
- `vmagent` (scrapes HAProxy's built-in exporter on `{{ vpn.tailscale_ip }}:8405` and the
  local node_exporter, remote-writes to secsvcs over the tailnet — option B of
  observability/04; local buffering covers secsvcs downtime).

Keep on the host: `haproxy` (needs the public IP and `chroot`), `headscale`, `tailscaled`,
`geoip_generator` (for now).

## Prerequisites

- `src/vpn/install_svcs.sh.j2` grows a `podman` case that installs Podman, copies
  `src/podman/*.sh` and `containers.conf`, and creates a `net.network` for the VPS.
- Secrets pipeline on the VPS (`/etc/opt/secrets/secrets.yaml.age`): check that
  `secret_update.sh vpn` already works there; add the vmagent remote-write credential.
- Every container binds to the tailnet IP or the Podman bridge only: no `PublishPort` on
  the public interface. Verify netavark's nftables rules don't open anything on it
  (`nft list ruleset` before and after; `nmap` from outside on the published ports).
- The VPS joins the image-updater rollout (image-updater/05) so its images are scanned
  like the others.
- Gatus/vmalert: `NodeDown` for the vpn node once its node_exporter is scraped
  (observability/01 excludes nothing on the VPS).

## Acceptance

- `systemctl list-units '*.service' | grep Homelab` on the VPS shows the three services.
- `up{instance="vpn.SITE"}` for node_exporter and haproxy is 1 in VictoriaMetrics; VPS
  journal lines appear in VictoriaLogs.
- An external port scan of the VPS shows only 80, 443 and the Headscale/SSH ports it
  showed before.
- Idle RAM on the VPS grew by less than 100 MB.

## Follow-up

- Containerise `geoip_generator` as a `.container` + timer once the above has run for a
  few weeks.

## Comments

- 2026-09-26: triage questions added during ticket review.
- 2026-09-27 maintainer: Podman for alignment; resource delta (~30 MB RAM, ~400 MB disk)
  accepted. Marked ready-for-agent.
