# ADR 0006: Declared node inventory instead of parsing configs at render time

Status: accepted (2026-09-27)

Amended: service entries also carry image facts (`upstream`, `build`, `update_last`, `containers`),
and `src/nodes.jinja` also outputs `images`, each node's images in update order, which the render
checks against the quadlets' `Image=`.

Amended: the inventory is split by node, `src/nodes/<node>/inventory.yml`, next to the rest of the
node's files; `render_src.sh` gathers them under `nodes:` in node-name order. The key reference is
in `src/nodes.jinja`.

Amended: the cross-checks live in `tools/check_rendered.py` and also cover the scripts named in
`commands[].run`, websvcs subdomains (each must be routed; only unlisted routes are allowed there)
and the OliveTin buttons (one per dispatcher case, none for a missing case).

Amended: services also carry `ip`, their container's host number, and `src/nodes.jinja` outputs
`addr`, each node's container addresses. Quadlets stay hand-written but take `IP=` from `addr`, as
does every config that names another container; the render checks the addresses are unique per
node and match each quadlet's `IP=`.

Amended: the derivation is `tools/inventory.py`, a uv script, in place of the Jinja macro file
`src/nodes.jinja`, which had grown into a program written in `{% do %}` statements and read
per-node vars through a private Jinja attribute. `tools/lib.sh`'s `template_vars` adds its output
to the template data as `inv:`, so templates read `inv.<name>` without an import, and
`check_rendered.py` reads the same lists. Its `dirs` subcommand replaces `tools/node_dirs.sh`, so the
debian-node test lives in one place. The key reference is in `tools/inventory.py`.

Amended: `tools/inventory.py` checks each file against a declared shape (its `NODE` table: the
allowed keys, each value's type and the keys that only make sense together) before deriving
anything, so a misspelled or mistyped key fails the render rather than being read as absent. The
per-key format checks `check_rendered.py` had (`ip` range, `upstream` ref, `image_updater_slot`
format) moved there; the cross-file checks stay. A CUE schema was prototyped for the same job and
rejected: it would add a binary to the laptop and CI for checks a page of Python expresses, and the
file format gains nothing.

## Context

Four scripts reverse-engineered template variables from other files at render time:
`parse_routes.sh` (subdomains from Traefik `routes.yml`), `parse_uptime_urls.sh` (Gatus URLs from
the Gatus config), `parse_dispatcher.sh` (sudoers grants and OliveTin buttons from `dispatcher.sh`)
and `gen_dispatch_cmds.sh` (dispatcher cases from `install_svcs.sh`, pasted in by hand). Each regex
was a place for a bug to hide (a hyphenated service name silently dropped out of the allowlist), and
the image updater would have added a fifth parser for install order. An earlier prototype
that generated routes, quadlets and secrets as well was judged too
complex.

## Decision

The node inventory (`src/nodes/<node>/inventory.yml`) declares only the facts those scripts
inferred, per node:

- `debian_services`, `services` and `commands`: the dispatcher entries. `services` is a mapping
  whose key order is the install order, so a service can carry attributes; today those are
  `subdomain`, `uptime` (the Gatus endpoint name), `uptime_path`, `uptime_tier` and
  `uptime_conditions`.
- `install_all_svcs: true` on the container VMs only.
- `dirs` per service: the `src/` dirs `upload_src.sh` ships to the node besides `src/base/` and
  its own node dir (`tools/node_dirs.sh`), so each node holds only the services it runs.
- `triggers` for the gaming VM's PowerShell allowlist.

`tools/render_src.sh` appends it to `vars.yml` as `nodes:`, since `jinjanate` takes a single data
file. `src/nodes.jinja` (imported, never rendered on its own) turns it into the dispatcher `case`
block, the sudoers command list, OliveTin command lists, the Unbound/HAProxy subdomain lists and the
Gatus internal endpoints. Every dispatcher (`dispatcher.sh.j2`, `Dispatcher.ps1.j2`) and sudoers
file is now a template over it.

Hand-written files stay the source for everything else: `routes.yml`, quadlets, `install_svcs.sh`,
`commands.sh`. The render cross-checks the inventory against them:

- a node's `services` are exactly the cases in its `install_svcs.sh`;
- `debian_services` and every `commands[].script` + name exist as cases;
- every node and service dir a node's files use is among the dirs it is shipped;
- subdomains are unique, and the secsvcs/homesvcs subdomains equal the `Host()` rules in that node's
  `routes.yml` (websvcs is the default route, so its subdomains only name uptime URLs).

## Consequences

- The dispatcher allowlist and the sudo grants come from the same list, so they still can't diverge
  (the property ADR 0005 relies on). The list can't drift from the scripts either, because the
  render fails.
- Adding a service means one `install_svcs.sh` case plus one `inventory.yml` line; a route on
  secsvcs/homesvcs also needs its `subdomain`.
- Dispatcher case order is canonical: debian services, services, `install_all_svcs`, then commands.
  OliveTin button order follows it.
- Later per-service facts go on the service entry rather than into a new parser: image facts for the
  image updater (upstream/build, update-last, extra quadlets) and the source directories for
  per-node uploads.
- Key order in `services` is meaningful; YAML tools that sort keys would change the install order.
- Debian nodes share one dispatcher and sudoers (`src/base/debian/`) selected by hostname.
