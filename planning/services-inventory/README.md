# Prototype: declarative service inventory

Proposal + working prototype for `services.yml`, one per node, as the single source of
truth for every cross-cutting fact about that node's services.

**Location note:** this lives under `planning/` (tracked since 2026-09-26) so it doesn't touch the clean
tree. If adopted, `services.yml` moves to `src/nodes/<node>/services.yml`, the schema to
`schema/services.schema.json`, and the templates into `tools/templates/`.

## Files

| File | What it is |
|---|---|
| `services.yml` | The inventory for **secsvcs**, complete: 15 services, 41 secrets |
| `services.schema.json` | JSON Schema (draft 2020-12) — the contract |
| `validate.py` | Schema + 7 cross-checks, and renders outputs |
| `templates/routes.yml.j2` | Generates Traefik `routes.yml` |
| `templates/dispatcher_cases.j2` | Generates `dispatcher.sh` case blocks |
| `compare.py` | Semantic diff: generated vs hand-written `routes.yml` |
| `rendered-*.yml/.sh` | Generator output |

## Run it

```bash
uv run --with pyyaml --with jsonschema --with jinja2 python validate.py services.yml --render
uv run --with pyyaml python compare.py
```

## Results

- **`routes.yml` round-trips exactly.** 17 routers and 11 backend services generated;
  semantic diff against the hand-written file is **0 differences** — rules, middleware
  chains (including the UI/API splits and header-regex matchers), TLS options, and
  backend URLs all match.
- **The generated dispatcher includes `ntfy-alertmanager`**, which is missing from
  `src/secsvcs/dispatcher.sh` today because `gen_dispatch_cmds.sh` matches
  `[a-zA-Z0-9_]+` and the name contains a hyphen. Reading data instead of regexing code
  removes the bug class, not just this instance.

## What the inventory owns, and what it doesn't

**Owns** — facts that today appear in 8–10 files at once: service identity (name, image,
container IP), install order and dependencies, routing (subdomain, port, scheme, router
splits), auth posture, the secret catalog, Postgres provisioning, internal-TLS cert
placement, scrape targets, uptime checks, and dashboard entries.

**Does not own** — quadlet bodies. `Exec=`, `Volume=`, `Environment=` stay in
`src/services/<name>/<name>.container.j2`, which pulls only `image` and `ip` from the
inventory. Generating whole quadlets from YAML is the trap that makes these systems
miserable; the file stays readable as a systemd unit.

## What it generates

`install_svcs.sh` cases · `dispatcher.sh` cases + `install_all_svcs` · `sudoers` ·
`traefik/routes.yml` · `prometheus.yml` scrape configs · `gatus/config.yaml` endpoints ·
`homepage/services.yaml` · `pg_init.sql` · `secrets_template.yaml` ·
`commands.sh` cert/key blocks · Authelia `access_control` + OIDC clients ·
Unbound `local-data` records · HAProxy SNI ACLs · quadlet `Image=`/`IP=`

Four scripts delete themselves: `parse_routes.sh`, `parse_uptime_urls.sh`,
`parse_dispatcher.sh`, `gen_dispatch_cmds.sh`.

## Checks the validator runs

1. JSON Schema conformance
2. Container IP uniqueness — replaces the `grep | sort | uniq -d` check in `render_src.sh`
3. Subdomain uniqueness per node
4. `requires:` targets exist **and** install earlier (catches ordering bugs statically)
5. Every secret has a real owner, or an explicit `remote:` marker
6. Unpinned images (warning) — currently flags 9
7. **Routes with no proxy auth**, printed every run — currently 6

Two CI checks worth adding that need the repo, not just this file: every `Secret=<name>`
in a quadlet must exist in the catalog, and every catalogued secret must be referenced by
something (catches typos and orphans in both directions).

Check 7 is the one I'd keep even if you adopt nothing else. `middlewares: []` in
`routes.yml` is easy to skim past; `auth: none` in a list of six is not.

## Design notes

**Escape hatches are mandatory.** `expose:` defaults to one simple router but accepts an
explicit list, and `match:` takes `any`, `browser`, or a raw Traefik matcher. Without
this, the VictoriaMetrics three-router split and ntfy's `!PathPrefix(/file/)` would have
forced you to rewrite working config to fit the schema. Traefik orders by rule length, so
the specific routers still beat the catch-all without explicit priorities.

**The secret catalog is a catalog, not a binding.** It holds name, owner, and generation
recipe; the quadlet keeps its own `Secret=name,type=env,target=ENV_VAR` mapping. Splitting
it this way means the inventory generates `secrets_template.yaml` without duplicating 60
env-var mappings, and CI still cross-checks the two.

**Dispatcher commands that aren't services** — `install_ca`, `install_certs`,
`install_keys`, `install_ssh_ca`, `install_dispatcher`, `install_mdns_repeater`,
`install_node_exporter`, `install_olive_tin_cert`, `copy_acme_certs`,
`build_haproxy_mapper` — need a sibling `commands:` block in the inventory. Not modelled
in this prototype; they're a flat list and straightforward to add.

**`vault` is deliberately absent.** It's wired through the dispatcher, sudoers, and
`install_all_svcs` today for a service that prints `TODO: Implement vault`.

## Migration path

Incremental, one output at a time — nothing is big-bang:

1. Land `services.yml` + schema + validator in CI. Generates nothing yet; it's just a
   second source that CI proves consistent with the hand-written files.
2. Switch `routes.yml` to generated (proven above: zero diff). Delete `parse_routes.sh`.
3. Switch `dispatcher.sh` + `sudoers`. Delete `parse_dispatcher.sh`, `gen_dispatch_cmds.sh`.
4. Switch `gatus/config.yaml`, then scrape configs, then `secrets_template.yaml`,
   `pg_init.sql`, `homepage`.
5. Point quadlets at `svc.image` / `svc.ip`.
6. Then `src/nodes/` vs `src/services/` reshuffle, and per-node rendering — both become
   easy once the inventory knows which services belong to which node.

Step 1 alone is worth landing: it makes drift a CI failure without changing any behaviour.
