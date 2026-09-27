# Router and network

Upgrades and configuration changes to the pfSense router VM on pve1, and network
performance across the system. Most pfSense configuration is click-configured and
recorded in `docs/guides/router.md.j2`, not in `src/router/`.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-pfsense-2.9-eim-nat.md) | Upgrade to pfSense CE 2.9.0; replace NAT-PMP / static-port NAT with EIM outbound NAT | `ready-for-human` | task |
| [02](issues/02-network-throughput-survey.md) | Measure network throughput on every path and find the bottlenecks | `ready-for-human` | research |
| [03](issues/03-headscale-acl-matrix.md) | Re-enable the group-based Headscale ACL matrix | `ready-for-human` | task |
| [04](issues/04-tailscale-no-snat.md) | Route subnets in the kernel on pfSense without SNAT, so LAN hosts see tailnet addresses | `ready-for-human` | task |
| [05](issues/05-node-expiry-and-tags.md) | Tag the infrastructure nodes and set a default node key expiry | `ready-for-human` | task |
