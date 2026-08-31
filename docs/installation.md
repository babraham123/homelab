# Installation

## Guide order of execution

Most of the config files are templatized to remove personal details. So first, render
the source locally and then start following the guides.
```bash
tools/render_src.sh /tmp/homelab-rendered
```

Note: the guides ending in `.j2` are templates; render them with
`tools/render_guides.sh <outdir>` for a readable copy, or read them in place — only
IPs and domains are templated.

Now follow the guides in this specific order:

1. Macbook setup — set up the dev machine: [mac_personal](guides/mac_personal.md.j2)
1. pve1 computer build — the always-on mini PC: [hardware specs](architecture.md#pve1--always-on-mini-pc)
1. Network build — AP, cabling, and the physical port plan: [architecture](architecture.md#network-gear-and-peripherals), [networking](networking.md#physical-and-logical-topology)
1. pve1 OS install — Proxmox with NIC passthrough: [proxmox](guides/proxmox.md.j2)
1. Router VM install — pfSense, VLANs, DNS, mDNS: [router](guides/router.md.j2)
1. secsvcs VM install, podman setup — [debian](guides/debian.md.j2), [podman](guides/podman.md.j2)
1. pve2 computer build — the on-demand tower: [hardware specs](architecture.md#pve2--on-demand-tower)
1. pve2 OS install — Proxmox, GPU passthrough, PBS: [proxmox](guides/proxmox.md.j2), [pve2](guides/pve2.md), [gpu](guides/gpu.md)
1. websvcs VM install, podman setup — [debian](guides/debian.md.j2), [podman](guides/podman.md.j2)
1. VPS VM setup, domain registrar — Linode, hardening, HAProxy: [vpn](guides/vpn.md.j2)
1. pve1 host: ssh certs, secrets and self-signed certs — [pve1](guides/pve1.md.j2)
1. VPN setup — Headscale + Tailscale mesh: [vpn](guides/vpn.md.j2)
1. pve1 host: acme certs — [pve1](guides/pve1.md.j2)
1. secsvcs services — auth, monitoring, alerting: [secure_services](guides/secure_services.md.j2)
1. VPN setup: user access — enroll personal devices: [vpn](guides/vpn.md.j2)
1. websvcs services — web apps: [web_services](guides/web_services.md.j2)
1. homesvcs services — home automation: [home_services](guides/home_services.md.j2)
1. gaming — Windows VM, GPU passthrough, Sunshine: [vm_windows](guides/vm_windows.md), [gaming](guides/gaming.md)
1. devtop — Linux desktop VM: [dev_desktop](guides/dev_desktop.md.j2)
