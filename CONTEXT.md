# Domain Glossary

Vocabulary used throughout this repo. Use these terms exactly; see
[docs/agents/domain.md](docs/agents/domain.md) for how agents consume this file.

## Nodes and naming

- **node** — a machine with a directory under `src/` holding its `install_svcs.sh`,
  `dispatcher.sh`, `commands.sh`, `sudoers`, and `traefik/` config. The nodes:
  `pve1`, `pve2`, `router`, `vpn`, `secsvcs`, `homesvcs`, `websvcs`, `devtop`,
  `gaming`. `src/debian/` and `src/macos/` are shared base setups, not nodes.
- **service** — any other directory under `src/`; one containerized (or host-level)
  application: its quadlet `*.container` file, volumes, and config templates.
- **container VM** — one of `secsvcs`, `homesvcs`, `websvcs`: a Debian VM running
  Podman quadlets with its own Traefik and its own container subnet.
- Guide names differ from node names: `secure_services` ↔ `secsvcs`,
  `home_services` ↔ `homesvcs`, `web_services` ↔ `websvcs`, `dev_desktop` ↔ `devtop`.
- **secproxy / homeproxy / webproxy** — the Traefik instance on secsvcs / homesvcs /
  websvcs respectively (also their dashboard subdomains).
- **pbs2** — the Proxmox Backup Server instance on pve2.

## Templating and deployment

- **vars.yml** — the gitignored file of real personal values (IPs, domain, users).
  **vars.template.yml** — its committed stand-in with fake values; used to render
  the public guides and quoted in all docs.
- **render** (first pass) — `tools/render_src.sh`: jinjanate every `*.j2` against
  `vars.yml` plus dynamically parsed variables, stripping one `.j2` extension.
- **second pass** — files named `*.j2.j2` survive the render as `*.j2` and are
  rendered again *at container startup* by `render_secrets.sh` / `render_host.sh`,
  injecting SOPS/AGE secrets or per-host parameters. Plaintext secrets never sit in
  the rendered tree.
- **parse scripts** — `tools/parse_routes.sh`, `parse_uptime_urls.sh`,
  `parse_dispatcher.sh`: derive template variables (subdomain lists, uptime URLs,
  sudoers command lists) from other configs, so those lists never drift by hand.
- **rendered tree** — `/root/homelab-rendered` on each node: the uploaded output of
  a render, the only thing scripts on the node execute from.

## Access model

- **manualadmin** — the interactive human SSH account on each node (file uploads,
  full sudo with password).
- **autoadmin** — the automation SSH account. Its key is bound to a ForceCommand.
- **dispatcher** — `src/<node>/dispatcher.sh`, the ForceCommand script that
  whitelists exact `$SSH_ORIGINAL_COMMAND` strings and maps them to `install_svcs.sh`
  / `commands.sh` invocations. Its command list is parsed into the node's generated
  sudoers file, so the whitelist and the sudo grants can't diverge.
- **commands.sh** — a node's grab-bag of root actions triggered remotely via the
  dispatcher (cert installs, HAProxy map builds, VM start/stop).

## Networking and trust

- **the three-tier ingress** — HAProxy (SNI passthrough on the VPS) → Tailscale mesh
  → per-node Traefik (TLS termination + ForwardAuth). Documented in
  [docs/networking.md](docs/networking.md).
- **site domain** — the public domain (`janedoe.com` in templates); **tail domain** —
  the Tailscale/Headscale mesh domain (`janedoe.ts.net` in templates).
- **internal CA** — the two-tier private X.509 hierarchy in `src/certificates/`
  (root + intermediate) for service-to-service TLS. Distinct from the **SSH CA**
  (host certificates) and from **ACME** (public Let's Encrypt certs via Traefik).
- **VLAN-ID-as-third-octet** — each VLAN's subnet embeds its ID: VLAN 10 →
  `192.168.10.0/24`. VLAN subnets are separate /24s, not carved from their parent
  interface's subnet.
