# Domain Glossary

Vocabulary used throughout this repo. Use these terms exactly; see
[docs/agents/domain.md](docs/agents/domain.md) for how agents consume this file.

## Nodes and naming

- **node** — a machine with a directory under `src/nodes/` holding, as applicable, its
  `install_svcs.sh`, `commands.sh` and `traefik/` config, and an `inventory.yml`; the router and
  gaming also hold their own dispatcher (and the router its `sudoers`). The nodes: `pve1`, `pve2`,
  `router`, `vpnsvcs`, `secsvcs`, `homesvcs`, `websvcs`, `devtop`, `gaming`. `src/base/` holds the
  setups they share (`debian/`, `podman/`, ...); `src/clients/` holds setups for devices that
  aren't nodes, such as the personal Mac.
- **service** — a directory under `src/services/`; one containerized (or host-level) application:
  its quadlet `*.container` file, volumes, and config templates.
- **container VM** — one of `secsvcs`, `homesvcs`, `websvcs`: a Debian VM running Podman quadlets
  with its own Traefik and its own container subnet.
- **secproxy / homeproxy / webproxy** — the Traefik instance on secsvcs / homesvcs / websvcs
  respectively (also their dashboard subdomains).
- **pbs2** — the Proxmox Backup Server instance on pve2.

## Templating and deployment

- **vars.yml** — the gitignored file of real personal values (IPs, domain, users).
  **vars.template.yml** — its committed stand-in with fake values; used to render the public guides
  and quoted in all docs.
- **render** (first pass) — `tools/render_src.sh`: jinjanate every `*.j2` against `vars.yml` plus
  the node inventory, stripping one `.j2` extension.
- **second pass** — files named `*.j2.j2` survive the render as `*.j2` and are rendered again on the
  node: by `render_host.sh` at install time (`install_svcs.sh`) for per-host parameters, or *at
  container startup* (`ExecStartPre`) by `render_secrets.sh` for SOPS/AGE secrets
  (`render_services.sh` for Fluent Bit's unit list). Plaintext secrets never sit in the rendered
  tree.
- **node inventory** — `src/nodes/<node>/inventory.yml`, one per node: per node, the dispatcher
  entries (services in install order, other commands) and each service's subdomain, Gatus endpoint
  and image facts. `src/nodes.jinja` derives the dispatcher cases, sudoers grants, DNS/SNI subdomain
  lists, uptime endpoints and image update order from it; the render (`tools/check_rendered.sh`)
  checks it against the scripts its dispatcher cases run, `routes.yml`, the quadlets' `Image=` and
  the OliveTin buttons.
- **image updater** — `src/base/podman/image_updater.sh`, on every node that runs quadlets: each
  night, and when a service is installed, it downloads (or builds) each image, passes it through the
  **scan gate** (Trivy: a fixable HIGH or CRITICAL CVE blocks it, unless a `.trivyignore` entry or
  `accept` overrides it) and loads it under its `localhost/` name, which is all a quadlet can run.
- **rendered tree** — `/root/homelab-rendered` on each node: the part of a render that node uses
  (`tools/node_dirs.sh`), the only thing scripts on the node execute from.

## Access model

- **manualadmin** — the interactive human SSH account on each node (file uploads, full sudo with
  password).
- **autoadmin** — the automation SSH account. Its key is bound to a ForceCommand; it has no file
  access (no sftp), and its home is root-owned.
- **dispatcher** — the ForceCommand script that allowlists exact `$SSH_ORIGINAL_COMMAND` strings
  and maps them to `install_svcs.sh` / `commands.sh` invocations. The Debian nodes share
  `src/base/debian/dispatcher.sh` and `sudoers`, which hold every Debian node's cases and grants
  and pick the node by hostname; the router and gaming have their own under `src/nodes/<node>/`.
  Dispatcher and sudoers are rendered from the same node inventory entries, so the allowlist and
  the sudo grants can't diverge. Commands carry data on stdin (`install_*`, via `send_files.sh`
  and `receive_files`) or stdout (`backup`, `copy_acme_certs`, `host_key`); the dispatcher's own
  output goes to stderr.
- **key_ids** — an inventory command's list of SSH certificate key IDs allowed to run it (`pve1`
  for anything that moves secrets or trust anchors). The dispatcher checks the login certificate
  through sshd's `ExposeAuthInfo`; OliveTin's key (`olive_tin`) gets no button for gated commands.
- **commands.sh** — a node's grab-bag of root actions triggered remotely via the dispatcher (cert
  installs, waking pve2, gaming VM start/stop, the repo archive).

## Networking and trust

- **the three-tier ingress** — HAProxy (SNI passthrough on the VPS) → Tailscale mesh → per-node
  Traefik (TLS termination + ForwardAuth). Documented in [docs/networking.md](docs/networking.md).
- **site domain** — the public domain (`janedoe.com` in templates); **tail domain** — the
  Tailscale/Headscale mesh domain (`janedoe.ts.net` in templates).
- **internal CA** — the two-tier private X.509 hierarchy in `src/nodes/pve1/certificates/` (root +
  intermediate) for service-to-service TLS. Distinct from the **SSH CA** (host certificates) and
  from **ACME** (public Let's Encrypt certs via Traefik).
- **VLAN-ID-as-third-octet** — each VLAN's subnet embeds its ID: VLAN 10 → `192.168.10.0/24`. VLAN
  subnets are separate /24s, not carved from their parent interface's subnet.
