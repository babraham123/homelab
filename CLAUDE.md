# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Infrastructure-as-code for a self-hosted homelab: configuration files, Jinja2 templates, and bootstrap scripts for running a zero-trust private cloud on Proxmox VMs with Podman containers.

## Key Commands

**Render and deploy to all servers:**
```bash
tools/deploy_src.sh
```

**Render templates locally** (requires `vars.yml`, `jinjanate`, `fd`/`fdfind`, `yamllint`, `jq`):
```bash
tools/render_src.sh /tmp/homelab-rendered
```

**Upload rendered files to a specific server:**
```bash
tools/upload_src.sh <hostname> /tmp/homelab-rendered
```

**Validate only** (run inside a rendered directory):
```bash
yamllint -c lint.yaml .
```

Rendering also validates YAML, JSON, and checks for duplicate container IPs.

## Architecture

### Nodes
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

### Templating System
- `vars.yml` contains specific/personal values for rendering (gitignored), `vars.template.yml` is an example
- All `*.j2` files are processed through Jinja2 via `jinjanate` at render time
- `*.j2.j2` files undergo a *second* render pass at service startup (e.g., for secrets injection via `src/podman/render_secrets.sh`)
- `tools/parse_routes.sh` and `tools/parse_uptime_urls.sh` generate additional variables dynamically during rendering

### Service Structure
Some directories under `src/` map to a node. They may contain:
- `install_svcs.sh` — Copies configs to `/etc/opt/<service>/` and container files to `/etc/containers/systemd/`, then reloads systemd
- `install_files.sh` - Moves files not present in the repo into their final destination
- `traefik/` — Reverse proxy routing rules (HTTP routers, middlewares)
- `secrets_template.yaml` — Template for SOPS-encrypted secrets
The remaining directories under `src/` typically map to a service. They may contain:
- `*.container` — Podman quadlet systemd unit files
- `*.volume` — Podman volume definitions
- Service configuration files

### Networking
- HAProxy handles frontline routing and rate limiting on vpn. Traffic is routed to either the VPN coordinator or the appropriate VM node.
- Tailscale on vpn funnels public traffic into the internal network. 
- Traefik handles TLS termination and routing for web services on each VM node.
- Unbound provides internal DNS on pfSense. Within the internal network traffic directly hits the correct VM node.
- Authelia enforces authentication and IDP. LLDAP manages users/groups.
- Internal certs are self-signed (managed in `src/certificates/`). External certs use ACME/Let's Encrypt via Traefik.

### Secrets
Secrets use SOPS + AGE encryption. A custom integration injects the secrets into podman containers. The `*.j2.j2` second-pass templates are also used to render secrets at container startup.

## Adding a New Service

From `docs/development.md`:
1. Add Traefik route config for the VM
1. Create service container and config files in `src/<service>/`
1. If cross-VM TLS is needed, add cert/key gen to `src/certificates/` and update `install_files.sh`
1. Add service to `install_svcs.sh`
1. Update Authelia config if OIDC auth is available (`src/authelia/`)
1. Add Gatus uptime check (`src/gatus/config.yaml`)
1. Add Homepage dashboard entry (`src/homepage/`)
1. Update the relevant guide in `docs/guides/`
