# 04. Scheduled iperf3 between pve1, pve2 and the VPS

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-23
Blocked by: 03

## Problem

Nothing measures what the internal paths carry. pve1 to pve2 crosses pfSense's routing on a
Celeron, so its forwarding rate, not the 2.5 GbE ports, is the likely ceiling. Home to the VPS
over Tailscale is what every public request rides on.

## Change

1. **Servers**, `iperf3` from Debian with a homelab unit (`iperf3_server.service`,
   `iperf3 -s -B <address>`), not Debian's own unit:
   - websvcs: bound to `websvcs.ip`; ufw from `secsvcs.ip` to 5201
   - vpnsvcs: bound to `vpnsvcs.tailnet_ip`; ufw in on `tailscale0` to 5201
2. **Headscale ACL**: `admin@` (the router's user, which SNATs secsvcs onto the tailnet) to
   `public@:5201`, plus a `tests` entry. The VPS gets no new outbound rule.
3. **Probe**, in `net_probe.py.j2` (03), one target list in the template; 03's runner orders,
   slots and busy-checks them:
   - `pve2`: slots 01, 07, 13, 19, apart from the speed test's so one hourly run never carries
     both. Busy check: pve2's `vmbr0` over 200 Mbit/s for the last 5 minutes (a Moonlight
     stream from the gaming VM crosses pfSense). Skipped as `unreachable` without trying when
     this run's ping to websvcs failed: pve2 is off.
   - `vps`: slot 04, once a day, since its reverse run is billed Linode egress (spec,
     constraints). No busy check: at 04 public traffic is negligible.
   - `iperf3 -c <target> -J -t 10 -O 2`, then the same with `-R`. Shorter runs, or a byte cap
     (`-n`), mostly measure TCP's ramp-up and read low on a fast link
   - A refused or timed-out connection records `homelab_iperf_up{path} 0` and no throughput;
     iperf3's "the server is busy" (someone's manual test) skips as `server_busy` and retries
     next hour
   - Metrics, labelled `path` (`pve2`, `vps`) and `direction` (`up` from secsvcs, `down` to it):
     `homelab_iperf_bits_per_second`, `homelab_iperf_retransmits`, `homelab_iperf_up`,
     `homelab_net_probe_last_success_timestamp_seconds{probe="iperf_<path>"}`
4. **Ping**, every run, first, to both targets: `ping -c 20 -i 0.2 -q`, parsed for
   `homelab_ping_rtt_seconds{path}` (average) and `homelab_ping_loss_ratio{path}`. Confirm ICMP
   passes the step 2 ACL; if it doesn't, add an `icmp` rule to the VPS beside it.
5. **Docs**: `docs/networking.md` (the ports), websvcs and vpnsvcs guides (ufw), `docs/services.md`.

## Acceptance

- With pve2 up, its slot run records both directions; the 04:00 run does the same for the VPS.
- Over a day, the VPS iperf3 runs once and its pings 24 times.
- Streaming from the gaming VM at a pve2 slot skips that test as `busy`.
- With pve2 off, the run succeeds, `homelab_iperf_up{path="pve2"} == 0`.
- `headscale policy check` passes with the new test.

## Comments

- 2026-10-24: code in. `iperf3_server` debian service on websvcs and vpnsvcs; it listens on every
  address and ufw admits only secsvcs, like node_exporter, rather than binding one address per
  host. The VPS rule is in `install_firewall.sh.j2`. pfSense routes subnet traffic without SNAT,
  so the Headscale ACL names `secsvcs`, not `admin@`: `secsvcs` → `public@:5201`, an ICMP rule,
  and a policy test.
