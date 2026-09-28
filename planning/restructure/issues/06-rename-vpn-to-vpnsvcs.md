# 06. Document every step to rename the vpn node to vpnsvcs

Status: resolved
Type: research
Repo: homelab
Source: user item 48
Blocked by: observability/04, backup-and-dr/09

## Deliverable

A checklist in `docs/guides/vpn.md.j2` (or a one-off `planning` runbook) covering all of
the below, in a safe order. The key trap: **`vpn.SITE` is the Headscale server URL that
every enrolled Tailscale client and the HAProxy `vpn_host` ACL depend on.** Renaming the
*node* is safe; renaming the *public DNS name* would strand every client. Recommend:
rename the node, keep `vpn.SITE` as a DNS alias (or add `vpnsvcs.SITE` and keep
`vpn.SITE` forever as the Headscale endpoint).

## Steps

1. **Repo:** `vars.yml`/`vars.template.yml` key `vpn:` → `vpnsvcs:`; grep and replace
   `{{ vpn.` in every template (`src/traefik/static.yml.j2` trustedIPs,
   `src/haproxy/haproxy.cfg.j2`, `src/dns/unbound.conf.j2`, `src/headscale/*`,
   `docs/**`). `git mv src/vpn src/vpnsvcs`; `render_src.sh` parse list (or `nodes.yml`),
   `deploy_src.sh` host list, `upload_src.sh` port-2202 special case; `CONTEXT.md` node
   list; `docs/architecture.md` tables/diagram.
2. **Linode host:** `hostnamectl set-hostname vpnsvcs` — required because
   `debian/commands.sh install_dispatcher` selects `src/$(hostname)/`. Update
   `/etc/hosts`.
3. **SSH:** `src/certificates/ssh_cert_gen.sh.j2` signs host certs for hostnames — re-issue
   the cert with both principals (`vpn.SITE`, `vpnsvcs.SITE`); update
   `src/macos/ssh.config.j2`, `src/olive_tin/ssh_config.j2`, `~/.ssh/known_hosts`
   entries, OliveTin actions that `ssh autoadmin@vpn`.
4. **DNS:** Unbound `local-zone` for the new name (keep the `transparent` `vpn.` record);
   registrar A record for `vpnsvcs.SITE` if you want the new name public.
5. **Headscale:** leave `server_url: https://vpn.SITE` unchanged unless you plan a
   client re-enrolment campaign; document that decision.
6. **HAProxy:** `acl vpn_host req.ssl_sni -i vpn.SITE` stays; add the new name if
   exposed.
7. **Monitoring:** Gatus endpoints, `node_exporter_vpn` scrape job (once
   observability/04 adds it), Grafana instance labels, Homepage entry.
8. **Escrow/DR docs** (backup-and-dr/09) reference the node name.
9. **Files added since this ticket was written** under `src/vpn/`: the dead-man checker
   (observability/10) and anything from observability/08.

## Acceptance

- The runbook exists, lists every file and host touched, and is ordered so each step can
  be verified before the next.
- It states the Headscale `server_url` decision explicitly.
- Execution is restructure/08.

## Answer

Runbook: [`planning/restructure/vpn-rename-runbook.md`](../vpn-rename-runbook.md). It has
9 phases, each ending in a check: preflight, repo commit, LAN DNS, SSH cert, hostname,
deploy, dispatcher, other consumers, monitoring. It also covers rollback.

- **Headscale `server_url`:** it stays `https://vpn.SITE` permanently, with no
  re-enrolment campaign. `vpn.SITE` becomes a service name for the Headscale endpoint,
  not the node name. The HAProxy `vpn_host` SNI, the Unbound `vpn.` transparent zone,
  the Authelia redirect URIs and `--login-server` stay too.
- **No registrar record.** The public `*` wildcard already resolves `vpnsvcs.SITE`.
  The LAN does need an Unbound `transparent` entry. Without it, pfSense's redirect zone
  sends `vpnsvcs.SITE` to websvcs, and `upload_src.sh`'s ping check passes against the
  wrong host.
- **SSH cert chicken-and-egg.** `ssh_cert_gen.sh` would connect to `vpnsvcs.SITE`
  before any cert names it. The first cert is signed by hand from pve1, connecting by
  the old name, with principals `vpnsvcs.SITE,vpn.SITE,IP`. The script keeps both
  names from then on.
- **Don't reinstall headscale.** Its install case upgrades to the latest release and
  overwrites the config. The rendered service configs don't change (same IP), so only
  `install_dispatcher` is needed.
- **Corrections to Steps:**
  - `render_src.sh` has no parse list anymore; it iterates over `nodes.yml`
    (restructure/01).
  - The SSH configs have no vpn entries. They need a new `Port 2202` block, which also
    fixes OliveTin's vpn buttons: they SSH to port 22, which ufw denies.
  - Gatus, Homepage and Grafana don't reference vpn today.
  - There's no `node_exporter_vpn` job (observability/04).
  - `secret_update.sh` keys its files by host name, and it lacks port 2202.
- **Guide:** rename `vpn.md.j2` → `vpnsvcs.md.j2` to follow restructure/04's rule.

## Comments
