# Runbook: rename the vpn node to vpnsvcs

One-off runbook for restructure/08. Produced by restructure/06. `SITE` is `site.url`,
`VPS_IP` is `vpnsvcs.ip`. Run the phases in order; each ends with a check that must pass
before the next.

## Decisions

- **`vpn.SITE` stays forever as the Headscale endpoint.** It is a service name, not the
  node name. Every enrolled client stores it as its login server: the Macs, Apple TV,
  pfSense, Debian hosts and guests. Changing it would mean re-enrolling every device,
  new Authelia OIDC redirect URIs and a new Let's Encrypt cert, and it buys nothing.
  These stay unchanged:
  - Headscale `server_url`, `tls_letsencrypt_hostname` (`src/headscale/headscale*.yaml.j2`);
  - Authelia's Headscale `redirect_uris` (`src/authelia/configuration.yml.j2:1756-1757`);
  - `--login-server https://vpn.SITE:443` (`src/headscale/tailscale.service.j2`, the guide);
  - HAProxy `acl vpn_host` and the `local_http(s)_vpn` backends (`src/haproxy/haproxy.cfg.j2`);
  - Unbound `local-zone: "vpn.SITE." transparent` (`src/dns/unbound.conf.j2:9`);
  - `docs/networking.md:110`.
- **`vpnsvcs.SITE` is for SSH and ops only.**
  - **Public DNS:** the `*` wildcard A record already resolves it to the VPS, so the
    registrar needs no new record.
  - **LAN DNS: this is the trap.** pfSense's system domain zone is `redirect`, so any
    `*.SITE` name without its own entry resolves to websvcs. Without an Unbound entry,
    `ping vpnsvcs.SITE` succeeds against websvcs, so `upload_src.sh`'s reachability
    check passes. The `scp -P 2202` after it then fails.
- **SSH host cert principals, permanently:** `vpnsvcs.SITE,vpn.SITE,VPS_IP`. Old
  callers and rollback keep working. `vpn.SITE` is the same box forever.
- **Metrics label values move to `vpnsvcs.SITE`.** This starts new series, and the
  old ones stay queryable. It only applies once observability/08 has landed (see
  phase 8).
- **Rename the guide** `docs/guides/vpn.md.j2` → `vpnsvcs.md.j2`, per restructure/04's
  rule that guide names match node names.
- **Don't reinstall headscale.** Its `install_svcs.sh` case downloads the latest
  release, which would be an unplanned upgrade, and overwrites
  `/etc/headscale/config.yaml`. `vpnsvcs.ip` has the same value as `vpn.ip`, so the
  rendered Headscale, HAProxy and Traefik configs differ only in comments. Only the
  dispatcher and sudoers need reinstalling.

## Phase 0: preflight

- Check which dependent tickets have landed; each one adds files to rename:
  - observability/08 (VPS containers, vmagent labels);
  - observability/10 (dead-man checker);
  - backup-and-dr/10 (vpn `backup_paths`);
  - restructure/02 (paths become `src/nodes/vpn…`).

  Each one that has landed adds rows to phase 1 or 8.
- Back up and pull the archive to pve1:
  `ssh -p 2202 autoadmin@vpn backup_full`, then
  `scp -P 2202 'autoadmin@vpn:/var/opt/backups/full/vpn-full-*.tar.zst' /root/backups/`.
- Record a baseline:
  - on the VPS: `headscale nodes list`;
  - on a Mac: `tailscale status`;
  - `curl -fsS https://vpn.SITE/health`.

## Phase 1: repo, one commit (agent)

| Where | Change |
|---|---|
| `vars.template.yml:41` | `vpn:` → `vpnsvcs:` |
| `{{ vpn.ip }}` → `{{ vpnsvcs.ip }}` | `src/traefik/static.yml.j2:45,48,55,58`; `test/traefik_static_test.yml.j2:23,26,33,36`; `src/headscale/headscale.yaml.j2:114`; `src/headscale/headscale_private.yaml.j2:112`; `src/go2rtc/config.yaml.j2:41` (comment); the guide (`:11,16,27,106`; `:16,27` also drop the stray `vpn.` prefix before the IP) |
| `git mv src/vpn src/vpnsvcs` | Inside: `dispatcher.sh.j2`: `inv.cases('vpnsvcs')`, usage comment. `sudoers.j2`: `inv.sudo_cmds.vpnsvcs`. `install_svcs.sh.j2:4` usage. `backup_full.sh`: `:3` guide path, `:5` usage, `:23` and `:66` archive prefix `vpnsvcs-full-` |
| `src/nodes.yml:48,55` | Key `vpnsvcs:`; `backup_full` path `src/vpnsvcs/backup_full.sh`. `render_src.sh` needs no change: it iterates over `nodes.yml` |
| `tools/upload_src.sh:20`, `tools/deploy_src.sh:18` | `vpnsvcs` |
| `src/certificates/ssh_cert_gen.sh.j2:9,24,45` | `vpnsvcs`; for vpnsvcs, add `vpn.SITE` to the `-n` principals |
| `src/dns/unbound.conf.j2` | Add `local-zone: "vpnsvcs.SITE." transparent` below the `vpn.` line |
| `src/olive_tin/config.yaml.j2:160-168` | Fieldset title, `inv.commands.vpnsvcs`, button title, `ssh autoadmin@vpnsvcs`, `id: vpnsvcs_…` |
| `src/olive_tin/ssh_config.j2`, `src/macos/ssh.config.j2` | Add `Host vpnsvcs.SITE vpn.SITE` / `Port 2202`. This also fixes an existing bug: OliveTin's vpn buttons SSH to port 22, which ufw denies |
| `src/headscale/headscale.yaml.j2:256` | Comment path `src/vpnsvcs/install_svcs.sh` |
| `src/headscale/headscale_acl.hujson.j2:12,21,89` | Guide name in the comments |
| `git mv docs/guides/vpn.md.j2 docs/guides/vpnsvcs.md.j2` | Node-name uses only:<ul><li>`src/vpn/` (`:55,119,122,143,216,241,250`)</li><li>`upload_src.sh vpn` (`:255`)</li><li>`autoadmin@vpn` (`:207,298,299,331`)</li><li>`vpn-full-` (`:294,299,305,319`)</li><li>"on vpn" (`:212,306`)</li><li>restore text `:324-325` becomes "`vpnsvcs.ip` … the `*` A record"</li></ul>Keep `vpn.SITE`, the `vpn` A-record step at `:60`, and `:86,124` |
| Guide links | `docs/installation.md:26,28,31`; `docs/debugging.md:379`; `docs/services.md:187`; the homesite blog posts. Add an `mkdocs-redirects` entry for the public URL (as in restructure/04) |
| `CONTEXT.md:11` | Node list |
| `docs/architecture.md:25,144,166` | Diagram label, section heading, table row |
| `docs/services.md:79-81,184-186` | Table rows; `ssh -p 2202 autoadmin@vpnsvcs backup_full`, `vpnsvcs-full` |
| `docs/networking.md:140,156` | "HAProxy on vpnsvcs" |
| `docs/debugging.md:409` | `scp -P 2202 manualadmin@vpnsvcs:sni.pcap .` |
| `docs/guides/pve1.md.j2:166,192,207` | `upload vpnsvcs`. `upload()` has no `-P`; give it a port argument for vpnsvcs |
| `docs/guides/pve1_recovery.md.j2:146` | Comment |

**Leave these alone:**

- `src/macos/vpn.sh.j2` and `docs/guides/mac_personal.md.j2:78`: the Mac's Tailscale
  toggle, not the node.
- "VPN" as a concept: `docs/security.md`, the `docs/debugging.md:342` heading.

**Existing bug, out of scope:** `src/pve1/secret_update.sh` has no port 2202, so it
can't reach the VPS today. observability/08 needs it, so fix it there.

**Checks:**

- This grep prints nothing. It is portable ERE, so it avoids `\b`, and it drops
  Headscale's upstream `*.vpn.example.com` comments. Before the rename it flags 56
  lines across 19 files.

  ```bash
  git grep -nE '\{\{ ?vpn[.]|[.]vpn([^a-z_]|$)|cases[(].vpn.[)]|src/vpn/|autoadmin@vpn([^a-z]|$)|_src[.]sh vpn([^a-z]|$)|vpn-full|vpn[.]md|"vpn"|(server|reachable[.]sh) vpn$' -- ':!planning' | grep -v 'example[.]com'
  ```

  CONTEXT.md and `docs/architecture.md` prose aren't covered, so check them by eye.
- `git grep -n 'vpn\.{{ site.url }}'` lists only the keep-list above.
- Render the old and new commits, each against its own `vars.template.yml`, in
  throwaway worktrees, and `diff -r` the outputs. The expected diffs are:
  - the node directory move;
  - OliveTin and the SSH configs;
  - Unbound, `ssh_cert_gen.sh`, `upload_src.sh` and `deploy_src.sh`;
  - `backup_full.sh`;
  - comments.

  `haproxy.cfg` and `traefik/static.yml` must be identical, and `headscale.yaml` may
  differ only in the comment at `:256`.

## Phase 2: LAN DNS (human, pfSense)

- Paste the rendered `unbound.conf` into Services → DNS Resolver → Custom options, then
  save.
- **Check:** `dig +short vpnsvcs.SITE` from the LAN returns `VPS_IP`, not websvcs's IP.
  So does `dig +short vpnsvcs.SITE @1.1.1.1`.

## Phase 3: SSH host cert (human, pve1)

This is a one-off manual signing. The rendered `ssh_cert_gen.sh` would SSH to
`vpnsvcs.SITE` before any cert names it, so this step connects by the old name instead.
`install_ssh_ca` moves all three uploaded files, so upload all three.

```bash
cd /root/ssh
scp -P 2202 autoadmin@vpn:/etc/ssh/ssh_host_ed25519_key.pub public/vpnsvcs.ssh_host_key.pub
addr=$(dig vpnsvcs.SITE +short)
ssh-keygen -s ca_ssh_host_key -I vpnsvcs -h -n "vpnsvcs.SITE,vpn.SITE,${addr}" -V +395d public/vpnsvcs.ssh_host_key.pub
chmod 444 public/vpnsvcs.ssh_host_key-cert.pub
scp -P 2202 public/vpnsvcs.ssh_host_key-cert.pub autoadmin@vpn:/home/autoadmin/ssh_host_key_cert.pub
scp -P 2202 ca_ssh_key.pub known_hosts autoadmin@vpn:/home/autoadmin
ssh -p 2202 autoadmin@vpn install_ssh_ca
rm public/vpn.ssh_host_key*
```

**Check:**

- `ssh-keygen -L -f public/vpnsvcs.ssh_host_key-cert.pub` lists all three principals.
- `ssh -p 2202 -o BatchMode=yes autoadmin@vpnsvcs.SITE nope` prints
  `Unauthorized command` with no host-key prompt.
- The same command against `vpn.SITE` behaves the same way.

## Phase 4: hostname (human, VPS)

Run phases 4–6 in one sitting. Between the hostname change and phase 6,
`install_dispatcher` can't find `src/$(hostname)/`, and after phase 5 the old sudoers
points at paths that are gone.

```bash
ssh -p 2202 manualadmin@vpn
sudo hostnamectl set-hostname vpnsvcs
sudo vim /etc/hosts   # 127.0.1.1 line: vpnsvcs.SITE vpnsvcs; keep the telemetry block
```

**Check:** `hostname` prints `vpnsvcs`, `hostname -f` prints `vpnsvcs.SITE`, and `sudo`
doesn't warn "unable to resolve host".

## Phase 5: deploy (human, Mac)

- Rename the `vpn:` key to `vpnsvcs:` in the local `vars.yml`.
- Run `tools/deploy_src.sh`.
- **Check:** the output has no `vpnsvcs upload failed`. On the VPS,
  `/root/homelab-rendered/src/vpnsvcs/` exists and `src/vpn/` doesn't.

## Phase 6: dispatcher (human, pve1)

- Run `ssh -p 2202 autoadmin@vpnsvcs install_dispatcher`.
- Run `ssh -p 2202 autoadmin@vpnsvcs backup_full`. This exercises the new sudoers path
  and writes the first `vpnsvcs-full-*` archive.
- Pull the archive to pve1.
- Delete the old `vpn-full-*` archives on the VPS; the retention glob no longer matches
  them. Keep pve1's copies as history.
- **Check:** both commands succeed, and `sudo cat /etc/sudoers.d/dispatcher` shows only
  `src/vpnsvcs/` paths.

## Phase 7: other consumers (human)

- **secsvcs:** `ssh autoadmin@secsvcs install_olive_tin`. **Check:** the OliveTin
  "vpnsvcs Install Dispatcher" button succeeds.
- **Mac:** re-copy `debian/ssh_config` per `mac_personal.md.j2`. If
  `ssh-keygen -F '[vpn.SITE]:2202'` finds a TOFU entry, remove it with `ssh-keygen -R`;
  the CA line covers both names.
- **pve1:** rename any `/root/secrets/vpn.yaml`, `vpn.yaml.age` and
  `vpn_id_ed25519.pub` to `vpnsvcs.*`, because `secret_update.sh` keys its files by
  host name.
- **Headscale:** tailscaled reports the new OS hostname. If `headscale nodes list`
  still shows `vpn`, run `headscale nodes rename -i ID vpnsvcs`. No ACL or config
  references the node's MagicDNS name.
- **Linode, optional:** the dashboard label. Leave the rDNS as `vpn.SITE`.
- **Check:**
  - `tailscale status` on a Mac matches the phase 0 baseline with no re-auth;
  - `curl -fsS https://vpn.SITE/health` succeeds;
  - a public site loads over 443.

## Phase 8: monitoring (only what exists at execution time)

Gatus, Homepage, Grafana and vmalert have no vpn references today: Gatus endpoints come
from `nodes.yml` `uptime`, and vpn has none. When the tickets below have landed, rename
their pieces as follows.

- **observability/08:**
  - `src/vpnsvcs/prometheus.yml.j2` instance relabels;
  - `--remoteWrite.label=host=vpnsvcs.SITE`;
  - the `vpnsvcs)` case in `render_host.sh`;
  - the `VpsMetricsAbsent` expression in `src/vmalert/configs/vps.yml`;
  - the HAProxy dashboard's filters;
  - the fluent-bit host field.
- **observability/10:** `src/vpnsvcs/deadman.*`, its install case, and any node name
  in its messages.
- **backup-and-dr/10:** the vpn `backup_paths` entry.

**Order:**

1. Silence `VpsMetricsAbsent` in Alertmanager.
2. Reinstall the VPS's vmagent, node_exporter and fluent-bit (their install cases are
   safe to rerun, unlike headscale's).
3. Reload vmalert.
4. Lift the silence.

**Check:** `up{host="vpnsvcs.SITE"} == 1` for every VPS job, with no gap longer than
the rename window.

## Acceptance (restructure/08)

- `ssh autoadmin@vpnsvcs install_dispatcher` works.
- `git grep -n '{{ vpn\.' src docs` finds nothing.
- Every Tailscale client stays connected without re-auth, and `vpn.SITE` answers
  on 443.
- The VPS's metrics, Gatus checks and dead-man checker (those that exist) report under
  `vpnsvcs`.

## Rollback

The cert names both hosts, so SSH by `vpn.SITE` keeps working at every step.

1. Run `hostnamectl set-hostname vpn` and restore `/etc/hosts`.
2. Revert the commit and the local `vars.yml` key.
3. Run `tools/deploy_src.sh`.
4. Run `ssh -p 2202 autoadmin@vpn install_dispatcher`.

Last resort: the Linode Lish console.
