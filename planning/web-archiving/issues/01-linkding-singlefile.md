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
- Doc for the maintainer (the guide or `docs/services.md`): browser setup on each
  client, following
  [linkding's archiving guide](https://linkding.link/archiving/#using-the-linkding-browser-extension).
  1. Install SingleFile and set its destination to "upload to a REST form API", with
     the URL `https://archive.{{ site.url }}/api/bookmarks/singlefile/`, the linkding
     REST token as the authorization token, `file` as the data field name and `url` as
     the URL field name.
  2. Install the linkding extension from the **same store** as SingleFile; the
     integration fails if they come from different stores, a trap on Edge. Point it
     at `https://archive.{{ site.url }}` with the same token.
  3. In the linkding extension, enable "Run Singlefile after adding new bookmark".
     Adding a bookmark, with tags such as `toread` (03), then uploads a snapshot.
  - Note the limits: the extension doesn't run SingleFile when an existing bookmark is
    edited, so re-snapshot with the SingleFile button.
  - Clients: desktop browsers and Firefox for Android. Check whether the linkding
    extension and SingleFile for Safari on iOS support this; if not, document the
    iOS fallback (share sheet to linkding, no snapshot).

## Acceptance

- The render passes, and `archive.` appears in DNS, Gatus, OliveTin, sudoers and the
  dispatcher.
- Logged in through Authelia, linkding opens as the Authelia user with no second login.
- From the LAN or VPN, adding a bookmark with the linkding extension creates it with
  its tags and an HTML snapshot uploaded by SingleFile. A SingleFile upload alone
  creates the bookmark with a snapshot.
  From outside both networks, `/api/` is refused.
- A backup run stages a database that opens with `sqlite3 … 'PRAGMA integrity_check'`.

## Comments
