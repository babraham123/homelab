# 08. Containerise the VPS's auxiliary services once Podman is installed there

Status: needs-triage
Type: task
Repo: homelab
Source: user item 50
Blocked by: 04

## Triage questions (maintainer)

The ticket can't be `ready-for-agent` until these are answered:

1. **Is Podman on the VPS wanted at all?** The Linode is the smallest plan (1 shared
   vCPU) and its only job is HAProxy + Headscale. Podman adds netavark, aardvark-dns, a
   bridge and image storage (~1 GB) to the one host that is on the public internet.
   Alternative that needs no Podman: install `node_exporter` and `fluent-bit` from
   Debian/upstream packages, bind them to the tailnet IP, and keep `geoip_generator` as
   the host unit it already is. That covers observability/04 option A and the VPS log
   shipping with two apt packages.
2. **Does `geoip_generator` gain anything from a container?** It is a Python script on
   a timer; the only reason to containerise it is uniformity.
3. **Is `vmagent` on the VPS needed**, or is a pull scrape over the tailnet from secsvcs
   (observability/04 option A) enough? vmagent only matters if you want the VPS to
   buffer when secsvcs is down, which the dead-man checker (observability/10) already
   handles differently.
4. **`ufw` and the Podman bridge:** netavark inserts its own nftables rules; confirm they
   can't publish a port on the public interface before any quadlet exists there.

If the answer to 1 is "no Podman", retitle this to "node_exporter and fluent-bit on the
VPS as host packages" and it becomes a small `ready-for-agent` task under
`src/vpn/install_svcs.sh.j2`.

## Scope (as written, assuming Podman)

After Podman is installed on the vpn node, move to quadlets under `src/vpn/`:
`geoip_generator` (as a `.container` + systemd timer, replacing `geoip_generator.service`
and `.py` on the host), `node_exporter`, `fluentbit` (journald → VictoriaLogs over the
tailnet), and `vmagent` (scraping HAProxy's built-in exporter + node_exporter locally,
remote-writing over the tailnet — option B of observability/04).

Keep on the host: `haproxy` (needs the public IP and `chroot`; a container gains
little), `headscale`, `tailscaled`.

## Prerequisites

- `src/vpn/install_svcs.sh.j2` grows a `podman` case that installs Podman, copies
  `src/podman/*.sh` and `containers.conf`, and creates a `net.network` for the VPS.
- Secrets pipeline on the VPS (`/etc/opt/secrets/secrets.yaml.age`) — check that
  `secret_update.sh vpn` already works there.
- `ufw`: new Podman bridge must not open anything on the public interface.

## Acceptance

- `systemctl list-units '*.service' | grep Homelab` on the VPS shows the four services;
  the host-level `geoip_generator.*` units are removed.

## Comments

- 2026-09-26: triage questions added during ticket review.
