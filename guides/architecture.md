# System Architecture

## Overview

The current system consists of 2 local machines and a small Linux VM the in Linode cloud. The VM hosts the controller for the overlay network (Headscale) and provides a public endpoint to tunnel traffic into the private network.

The first machine (PVE1) is a single board computer with 4 2.5GHz ethernet ports. It serves as a router for the home network and runs the most critical web apps. The second machine (PVE2) is a custom PC tower that runs everything else (other web apps, game server, media server, etc). The tower has a bunch of peripherals (GPU, hard drives, optical drive, etc) and can be turned off overnight. Other devices include a PoE switch, a WiFi 6 capable AP and a 1500VA UPS. My main concern was balancing capability and power consumption.

Logically, the home network is divided into 4 subnets, one for the WiFi network, the SBC, the PC tower and the switch. In the future I'll add firewall rules and VLANs. The router runs pfSense CE with a number of services, including Unbound DNS and a Tailscale client. For public traffic, the cloud VM runs a Tailscale client and HAProxy to route HTTP requests to either to the SBC or the tower.

Both machines run the Proxmox hypervisor to virtualize different workloads. On the SBC there's a FreeBSD VM running pfSense, a Debian VM running the critical web apps (secsvcs) and a Debian VM for Home Assistant. On the tower there's a Debian VM running the rest of the web apps (websvcs), a Windows VM for gaming, a Debian VM for machine learning development (devtop) and a MacOS VM for a few desktop apps. The last 3 VMs are only run on an adhoc basis. All of the web apps are run via Podman containers. I use a neat feature called Podman Quadlet to run the containers as Systemd services.

Both secsvcs and websvcs run Traefik to further route requests to a particular container. Traefik also manages the ACME certificates and terminates most HTTPS traffic. secsvcs runs critical apps like Authelia (single sign on gateway), LLDAP (user management), VictoriaMetrics (metrics database), VictoriaLogs (logs indexer), vmalert (alerting), Grafana (dashboards), Gatus (uptime monitoring) and Postgres. There is limited traffic between containers, carefully filtered and encrypted with TLS (via self-signed certificates). Secrets are stored in an AGE encrypted file and passed to containers via a custom Podman Secrets integration.

## Hardware

## Networking

### DNS

//

### Security

#### Certificates

//

## Storage

### on PVE2

- SATA SSD
  One big FS on host, pass thru to websvcs VM
  - Shared NFS drive: common folders and personal media
  - Plex media (NFS possible but slower)
- NVMe SSD
  A thin LVM pool with virtualized partitions for each VM. Check speed
  - Proxmox OS 8G
  - ISOs 16G
  - VMs rest
  - Games (LV to run NTFS, separate from Windows VM for faster backups) 256
- HDD
  - VM backups
  - monthly LVM backups
  - Maybe also ML datasets
