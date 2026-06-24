# Architecture

## Nodes

| Hostname | Purpose | Host Machine |
|----------|---------|--------------|
| pve1 | Proxmox hypervisor (SBC), always on | self |
| pve2 | Proxmox hypervisor (tower), intermittent, has accelerators | self |
| vpn | VPN coordinator and public endpoint (Headscale, Tailscale, HAProxy) | self |
| router | Routing, firewall and VLAN management (pfSense) | pve1 |
| secsvcs | Core services: auth, user management, monitoring (Authelia, LLDAP, etc.) | pve1 |
| homesvcs | Home automation (Home Assistant, MQTT, ESPHome) | pve1 |
| websvcs | Non-critical supporting services | pve2 |
| devtop | Linux desktop for development and general usage | pve2 |
| gaming | Windows desktop for PC gaming | pve2 |

Notes:
- **vpn**: The cloud VM that hosts the VPN coordinator. It also funnels public traffic into my private network.
- **PVE1 / SBC**: The singe board computer that runs the router software, critical web apps and Home Assistant. The base OS manages container secrets, certificates and general provisioning, so it should be the most secure host in the system.
- **PVE2 / PC Tower**: The custom desktop computer that runs the rest of the web apps and various GUI based OSes. These web apps are generally user facing and may contain personal information. This host may be turned off when not in use.

## Networking

- HAProxy handles frontline routing and rate limiting on vpn. Traffic is routed to either the VPN coordinator or the appropriate VM node.
- Tailscale on vpn funnels public traffic into the internal network. 
- Traefik handles TLS termination and routing for web services on each VM node.
- Unbound provides internal DNS on pfSense. Within the internal network traffic directly hits the correct VM node.
- Authelia enforces authentication and IDP. LLDAP manages users/groups.
- Internal certs are self-signed (managed in `src/certificates/`). External certs use ACME/Let's Encrypt via Traefik.

## Containers

TODO: fill in

### Secrets

Secrets use SOPS + AGE encryption. A custom integration injects the secrets into podman containers. The `*.j2.j2` second-pass templates are also used to render secrets at container startup.
