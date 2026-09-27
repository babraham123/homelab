# ADR 0006: Declared node inventory instead of parsing configs at render time

Status: accepted (2026-09-27)

## Context

Four scripts reverse-engineered template variables from other files at render time:
`parse_routes.sh` (subdomains from Traefik `routes.yml`), `parse_uptime_urls.sh` (Gatus
URLs from the Gatus config), `parse_dispatcher.sh` (sudoers grants and OliveTin buttons
from `dispatcher.sh`) and `gen_dispatch_cmds.sh` (dispatcher cases from
`install_svcs.sh`, pasted in by hand). Each regex was a place for a bug to hide (a
hyphenated service name silently dropped out of the whitelist), and the image updater
would have added a fifth parser for install order. An earlier prototype
(`planning/services-inventory/`) that generated routes, quadlets and secrets as well was
judged too complex.

## Decision

`src/nodes.yml` declares only the facts those scripts inferred, per node:

- `debian_services`, `services` and `commands`: the dispatcher entries.
  `services` is a mapping whose key order is the install order, so a service can carry
  attributes; today those are `subdomain`, `uptime` (the Gatus endpoint name) and
  `uptime_path`.
- `install_all_svcs: true` on the container VMs only.
- `triggers` for the gaming VM's PowerShell whitelist.

`tools/render_src.sh` appends it to `vars.yml` as `nodes:`, since `jinjanate` takes a
single data file. `src/nodes.jinja` (imported, never rendered on its own) turns it into
the dispatcher `case` block, the sudoers command list, OliveTin command lists, the
Unbound/HAProxy subdomain lists and the Gatus internal endpoints. Every dispatcher
(`dispatcher.sh.j2`, `Dispatcher.ps1.j2`) and sudoers file is now a template over it.

Hand-written files stay the source for everything else: `routes.yml`, quadlets,
`install_svcs.sh`, `commands.sh`. The render cross-checks the inventory against them:

- a node's `services` are exactly the cases in its `install_svcs.sh`;
- `debian_services` and every `commands[].script` + name exist as cases;
- subdomains are unique, and the secsvcs/homesvcs subdomains equal the `Host()` rules
  in that node's `routes.yml` (websvcs is the default route, so its subdomains only
  name uptime URLs).

## Consequences

- The dispatcher whitelist and the sudo grants come from the same list, so they still
  can't diverge (the property ADR 0005 relies on). The list can't drift from the
  scripts either, because the render fails.
- Adding a service means one `install_svcs.sh` case plus one `nodes.yml` line; a route
  on secsvcs/homesvcs also needs its `subdomain`.
- Dispatcher case order is canonical: debian services, services, `install_all_svcs`,
  then commands. OliveTin button order follows it.
- Later per-service facts go on the service entry rather than into a new parser: image
  facts for the image updater (upstream/build, update-last, extra quadlets) and the
  source directories for per-node uploads.
- Key order in `services` is meaningful; YAML tools that sort keys would change the
  install order.
