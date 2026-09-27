# 02. Measure network throughput on every path and find the bottlenecks

Status: ready-for-human
Type: research
Repo: homelab
Source: maintainer request 2026-09-26
Blocked by: 01

## Why after 01

The pfSense 2.9 upgrade and the NAT change alter the routing and Tailscale paths, and
the numbers should describe the router you'll keep. Optionally run test 3 once before 01
for a before/after.

## Known suspects (from the repo)

| Suspect | Why |
|---|---|
| **pfSense on a Celeron N5105 routes every inter-subnet flow** | pve1 VMs ↔ pve2, LAN ↔ anything, WiFi ↔ servers. pf + packages on 4 small cores may not reach 2.5 GbE line rate |
| **pve2's uplink** | `eno1`, probably the board's onboard Intel I219 (1 GbE), with `tso off gso off` from the crash workaround in `docs/guides/proxmox.md.j2:41`, which shifts segmentation to the CPU. Everything pve2 serves, including every pve1 → pbs2 backup, is capped by it |
| **pve1 VMs reach pfSense over virtio on `vmbr0`** | vhost threads share the N5105 with the router VM |
| **Tailscale** | WireGuard CPU cost on the smallest Linode (1 shared vCPU), DERP relay vs direct, MTU 1280 plus the MSS clamp on the VPS |
| **Public ingress** | internet → HAProxy (VPS, 1 vCPU) → tailnet → Traefik TLS → app. VPS egress is the cap |
| **WiFi** | EAP660 HD, per VLAN |

## Method

Install `iperf3` on the Debian nodes, pve1, pve2, the VPS and a laptop. On pfSense use
the `iperf` package. For each pair run:
- `iperf3 -c <peer> -t 20` and `-R` (both directions);
- `-P 4` (parallel);
- WiFi and tailnet only: `-u -b <rate>` for loss and jitter.

During each run, capture:
- CPU: pfSense `top -aSH`, PVE host `mpstat -P ALL 1` (watch `vhost-*` and `ksoftirqd`),
  VPS `top`;
- link state: `ifconfig igcN | grep media` on pfSense, `ethtool eno1` on pve2;
- path MTU: `ping -M do -s <size>` (Linux) / `ping -D -s` (FreeBSD).

| # | Path | Hops exercised |
|---|---|---|
| 1 | secsvcs ↔ homesvcs | vmbr0 only (virtio baseline, no router) |
| 2 | secsvcs ↔ pfSense | vmbr0 → router VM |
| 3 | secsvcs ↔ websvcs, and pve1 ↔ pbs2 | routed via pfSense `igc2` to pve2. **The backup path.** Also note throughput from a real vzdump task log |
| 4 | pve2 ↔ wired LAN2 device | routed `igc2` → `igc3` |
| 5 | WiFi laptop (trusted VLAN) ↔ websvcs and ↔ secsvcs | AP + trunk + routing. Repeat on the IoT VLAN if a client can run iperf |
| 6 | WAN | `speedtest` (Ookla CLI or librespeed-cli) from pfSense and from secsvcs: NAT overhead vs ISP plan |
| 7 | Tailscale | LAN node ↔ VPS; phone on mobile data ↔ secsvcs. `tailscale status` / `tailscale ping` to confirm direct vs DERP |
| 8 | Public ingress | from a phone on mobile data, download a large file from `www.SITE` via HAProxy; compare with the same file from the LAN |
| 9 | Containers | container ↔ container on one node, host ↔ container (netavark bridge). Use a throwaway `iperf3` container |
| 10 | Latency baseline | `mtr` from a WiFi client to secsvcs, to the VPS and to 1.1.1.1; DNS lookup time via Unbound |

## Deliverable

- A "Performance" section in `docs/networking.md`: per path, measured vs expected
  (2.5 GbE ≈ 2.3 Gbit/s TCP, 1 GbE ≈ 940 Mbit/s, WiFi 6 client typically 500–900
  Mbit/s, VPS egress per the Linode plan), plus the limiting resource (link, CPU on which
  box, or MTU).
- A follow-up ticket for each bottleneck worth fixing. Likely candidates:
  - a 2.5 GbE NIC for pve2, and re-testing whether the TSO/GSO workaround is still needed;
  - pfSense tuning or offload settings;
  - pbs2's datastore disk speed if backups are disk-bound rather than network-bound;
  - a bigger VPS if public ingress matters.
- Record the backup-path throughput and expected run time for a full vzdump in
  backup-and-dr/01, which sizes the orchestrator's window.
- Optional: a nightly WAN speed test exporter into VictoriaMetrics, if trends are
  wanted.

## Comments
