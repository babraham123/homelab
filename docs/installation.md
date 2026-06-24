# Installation

## Guide order of execution

Most of the config files are templatized to remove personal details. So first, render the source locally and then start following the guides.
```bash
tools/render_src.sh /tmp/homelab-rendered
```

Now you will follow the guides in a specific order. TODO: elaborate, add links

1. macbook setup
1. pve1 computer build
1. Network build
1. pve1 OS install
1. router VM install
1. secsvcs VM install, podman setup
1. pve2 computer build
1. pve2 OS install
1. websvcs VM install, podman setup
1. VPS VM setup, domain registrar
1. pve1 host: ssh certs, secrets and self-signed certs
1. VPN setup
1. pve1 host: acme certs
1. secsvcs
1. VPN setup: user access
1. websvcs
1. gaming
1. devtop
