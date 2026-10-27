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

## Change

- On vpnsvcs: `systemctl status crowdsec-firewall-bouncer`, `journalctl -u crowdsec-firewall-bouncer
  -n 50`, `nft list ruleset | grep -A5 crowdsec`, `curl -m 3 10.93.0.1:60601/metrics` from the
  host and from inside the vmagent container.
- Fix whichever it is: the LAPI key or URL in the bouncer config, or an nftables rule allowing the
  podman subnet to reach the gateway's `60601` (and `8405`, `9090` for the other exporters if they
  share the symptom, though those scrape fine today).
- Add the bouncer unit to vpnsvcs' `homelab_services` so its journal is queryable next time.

## Acceptance

- `cscli bouncers list` on secsvcs shows the vpnsvcs bouncer's last pull within the last minute.
- `up{job="crowdsec_firewall_bouncer"} == 1` and `fw_bouncer_dropped_packets` exists.
- `TargetDown` and `CrowdsecBouncerStale` resolve.
- `{hostname="vpnsvcs", service="crowdsec-firewall-bouncer"}` returns lines in VictoriaLogs.
