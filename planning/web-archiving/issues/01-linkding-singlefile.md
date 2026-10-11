# 01. Run linkding on websvcs with SingleFile uploads

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-11

## Problem

With ArchiveBox gone there's nowhere to keep bookmarks or full-page copies of pages,
including pages behind a login.

## Change

Follow "Add a new service" in `docs/development.md`, with `src/isso/` as the model.

- `src/linkding/linkding.container.j2`:
  - `Image=docker.io/sissbruecker/linkding:latest` (the base image, not
    `latest-plus`), `ContainerName=linkding`, `HostName=archive.{{ site.url }}`,
    `IP={{ websvcs.container_subnet }}.17`, port 9090, `NoNewPrivileges=true`,
    `AutoUpdate=registry` like the other quadlets.
  - Data: `/var/opt/linkding:/etc/linkding/data`, a host path, since snapshots
    accumulate there.
  - Auth proxy: `LD_ENABLE_AUTH_PROXY=True`,
    `LD_AUTH_PROXY_USERNAME_HEADER=HTTP_REMOTE_USER`,
    `LD_AUTH_PROXY_LOGOUT_URL=https://dash.{{ site.url }}`,
    `LD_CSRF_TRUSTED_ORIGINS=https://archive.{{ site.url }}`. Check the names against
    linkding's `docs/src/content/docs/options.md` before writing them.
- `src/websvcs/install_svcs.sh` case `linkding`; `src/nodes.yml` entry
  `linkding: {subdomain: archive, uptime: linkding}` (add `uptime_path` if `/` is
  not a 200 behind Authelia).
- Traefik router and service in `src/websvcs/traefik/routes.yml.j2`
  (`http://archive.{{ site.url }}:9090/`).
- Authelia: SingleFile sends `Authorization: Bearer <token>`, which Authelia's forward
  auth doesn't accept. Add a rule before the generic `*.{{ site.url }}` rules that
  bypasses `resources: ['^/api/']` on `archive.{{ site.url }}`, limited to the
  `internal` and `vpn` networks. linkding still enforces the token.
- Homepage tile under Productivity, and the install line in
  `docs/guides/web_services.md.j2`.
- Backups: stage the SQLite database consistently in `src/websvcs/backup.sh.j2`, using
  linkding's own backup command if it has one, or `sqlite3 .backup` like
  `src/vpnsvcs/backup.sh.j2`. Decide whether snapshot files are backed up or excluded
  as large, and say which in the header comment.
- Doc for the maintainer (the guide or `docs/services.md`): SingleFile setup on each
  client. Set "upload to a REST form API" to
  `https://archive.{{ site.url }}/api/bookmarks/singlefile/`, the token to the linkding
  REST token, the data field name to `file`, and the URL field name to `url`.
  Clients: desktop extension, Firefox for Android, and SingleFile for Safari (check
  whether the iOS build supports REST upload).

## Acceptance

- The render passes, and `archive.` appears in DNS, Gatus, OliveTin, sudoers and the
  dispatcher.
- Logged in through Authelia, linkding opens as the Authelia user with no second login.
- From the LAN or VPN, a SingleFile upload creates a bookmark with an HTML snapshot.
  From outside both networks, `/api/` is refused.
- A backup run stages a database that opens with `sqlite3 … 'PRAGMA integrity_check'`.

## Comments
