# 01. Minimal per-node inventory that replaces parse_routes/parse_uptime_urls/parse_dispatcher/gen_dispatch_cmds

Status: ready-for-agent
Type: prototype
Repo: homelab
Source: user item 57 (previous prototype in planning/services-inventory judged too complex)

## Goal

Not a full data model. Only the facts the four `parse_*`/`gen_*` scripts reverse-engineer
from other files, expressed once, so those scripts can be deleted:

| Script | Variable it produces | Replace with |
|---|---|---|
| `parse_routes.sh <node>` | `<node>_subdomains` | list of subdomains per node |
| `parse_uptime_urls.sh` | `uptime_internal_urls` | derived from the same list + per-service health path |
| `parse_dispatcher.sh <node>` | `<node>_commands`, `<node>_sudo_cmds` | services list + static commands list |
| `gen_dispatch_cmds.sh <node>` | dispatcher case text | template loop over services |

## Shape (`src/nodes.yml`, one file, ~60 lines total)

```yaml
secsvcs:
  services:            # install order; name == install_svcs.sh case == quadlet
    - postgres
    - lldap
    - authelia
    - traefik
    - ...
  subdomains:          # only services with a Traefik route
    lldap: ldap
    authelia: auth
    traefik: secproxy
    victoriametrics: metrics
    ...
  uptime_paths:        # optional override; default "/"
    ntfy: /v1/health
  commands:            # non-service dispatcher entries; whether they need sudo
    - {name: install_keys,   script: secsvcs/commands.sh, sudo: true}
    - {name: build_haproxy_mapper, script: secsvcs/commands.sh, sudo: false}
    - {name: install_ssh_ca, script: debian/commands.sh, sudo: true}
homesvcs: ...
websvcs: ...
vpn: ...
pve1: ...
```

## Mechanism

`jinjanate` accepts more than one data file: `jinjanate -o out tmpl vars.yml src/nodes.yml`.
So `render_src.sh` drops the `{ head vars.yml; parse_*.sh ...; } > all_vars.yml`
assembly entirely and templates loop over `nodes.secsvcs.subdomains` etc. Templates to
convert: `src/dns/unbound.conf.j2`, `src/haproxy/haproxy.cfg.j2`,
`src/<node>/sudoers.j2`, `src/gatus/config.yaml.j2` (endpoints loop), and
`src/<node>/dispatcher.sh` becomes `dispatcher.sh.j2` with the case block generated.
`routes.yml`, quadlets, `install_svcs.sh` stay hand-written.

## Validation (in `render_src.sh` / pre-commit)

- every `services[]` entry has a `X)` case in that node's `install_svcs.sh`;
- every `subdomains` key is in `services`; subdomains unique across all nodes;
- every `commands[].script` file exists.

## Acceptance

- Rendered `unbound.conf`, `haproxy.cfg`, `sudoers`, `gatus/config.yaml` and each
  `dispatcher.sh` are byte-identical (or semantically identical via yq) to today's
  output *except* for the `ntfy-alertmanager` case that the regex bug currently drops.
- The four scripts are deleted.

## Comments

- 2026-09-26: image-updater/02 adds `tools/parse_images.sh`, another script that
  reverse-engineers install order and quadlet labels. Fold it into `nodes.yml` here.
