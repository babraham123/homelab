# 14. The CrowdSec firewall bouncer on vpnsvcs is neither pulling decisions nor serving metrics

Status: needs-triage
Type: task
Repo: homelab
Source: queries.md verification 2026-10-27

## Problem

Two alerts have been firing together: `TargetDown` for `job="crowdsec_firewall_bouncer"` and
`CrowdsecBouncerStale` (the LAPI on secsvcs counts no pulls from the `vpnsvcs` bouncer). No
`fw_bouncer_*` series exists in the 90-day window and `up{job="crowdsec_firewall_bouncer"}` has
never been 1 in 30 days, so the bouncer has not worked since vpnsvcs was containerised (08).

vmagent on vpnsvcs reports the scrape as a connection that never completes, not a refusal:

```text
cannot scrape target "http://10.93.0.1:60601/metrics": net/http: request canceled while
waiting for connection (Client.Timeout exceeded while awaiting headers)
```

That is the shape of a packet dropped by nftables rather than a closed port. The bouncer writes
its own nftables table with `input` hooked (`crowdsec-firewall-bouncer.yaml.local.j2`), and
`prometheus.listen_addr` is the podman bridge gateway, so a likely cause is the bouncer's or the
host's ruleset dropping the bridge-to-gateway traffic. The stale LAPI pulls say the process is
unhealthy independently of the metrics port, though: it may be crash-looping on the LAPI key or
URL after the move. Its journal is not shipped to VictoriaLogs (no `crowdsec-firewall-bouncer`
unit in vpnsvcs' `homelab_services`), so the node's journal is the only record.

## Findings (2026-10-28)

The bouncer section of the VPS guide (`docs/guides/vpnsvcs.md.j2`, "CrowdSec") has not been done
on the current build:

- `crowdsec-firewall-bouncer.service` is not in vpnsvcs' Homelab unit list, which node_exporter
  and Fluent Bit both filter on; the list was rebuilt when node_exporter restarted today.
- The LAPI counts requests only from the three Traefik bouncers and logs no auth failures, so
  nothing contacts it with the vpnsvcs key.
- The scrape dies waiting for a connection while 8405 and 9090 on the same gateway IP work:
  ufw's default deny without the guide's `60601` rule, same shape as hardware-monitoring 06.
- Today's `install_some_svcs` did not run on vpnsvcs (HAProxy and vmagent still date from
  2026-10-26). The install case dies when `/etc/opt/secrets/crowdsec_bouncer_key` is empty, which
  would abort a run at that step.

## Change

- Do the guide's CrowdSec section on vpnsvcs: the key file, the two ufw rules (egress 8455 over
  tailscale0, ingress 60601 from vmagent), then `install_crowdsec_firewall_bouncer`.
- Move the ufw exporter rules into `install_network.sh`, derived from the inventory, so a reset
  keeps them (hardware-monitoring 06's follow-up).
- Add the bouncer unit to vpnsvcs' `homelab_services` so its journal is queryable next time.

## Acceptance

- `cscli bouncers list` on secsvcs shows the vpnsvcs bouncer's last pull within the last minute.
- `up{job="crowdsec_firewall_bouncer"} == 1` and `fw_bouncer_dropped_packets` exists.
- `TargetDown` and `CrowdsecBouncerStale` resolve.
- `{hostname="vpnsvcs", service="crowdsec-firewall-bouncer"}` returns lines in VictoriaLogs.
