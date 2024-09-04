# Homelab

Configuration and bootstrapping scripts for a local, private cloud (aka a homelab). The goal is to create a zero-trust environment to serve web apps, manage media and work on tech projects. I strongly prioritized open source and self hosted software. High availability and automatic provisioning are non-goals given the scale of the system.

Note, this setup is just one way to implement a homelab. I've configured things with a certain set of goals in mind that might not fit everyone. Also there are probably great tools and best practices  that I'm simply unaware of. Either way, treat these guides and bash scripts as more of a source of inspiration.

For more details see the [Architecture](./docs/architecture.md), [Terminology](./docs/terminology.md) and [Discussion](./docs/discussion.md).

## Guide order of execution

Most of the config files are templatized to remove personal details. So first, render the source locally and then start following the guides. 
Once the network, hosts and VMs are setup, you'll download the repo onto the SBC and render all of the templates. From there most of the guides will copy files, configure services and other chores.

1. pve1 computer build
1. Network build
1. pve1 OS install
1. pfSense VM install
1. secsvcs VM install, podman setup
1. pve2 computer build
1. pve2 OS install
1. websvcs VM install, podman setup
1. VPS VM setup, domain registrar
1. pve1 host: self-signed certs and secrets
1. VPN setup
1. pve1 host: acme certs
1. secsvcs
1. websvcs
1. gaming
1. devtop
