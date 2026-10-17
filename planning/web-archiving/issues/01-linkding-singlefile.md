# 01. Run linkding on websvcs with SingleFile uploads

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-11

## Problem

With ArchiveBox gone there's nowhere to keep bookmarks or full-page copies of pages,
including pages behind a login.

## Change

Follow "Add a new service" in `docs/development.md`, with `src/services/isso/` as the model.

- `src/services/linkding/linkding.container.j2`:
  - `Image=localhost/sissbruecker/linkding:latest-plus`, with
    `upstream: docker.io/sissbruecker/linkding:latest-plus` in the inventory entry so
    image_updater pulls and scans it. `ContainerName=linkding`,
    `HostName=archive.{{ site.url }}`, `IP={{ websvcs.container_subnet }}.17`, port
    9090, `NoNewPrivileges=true`, `AutoUpdate=local` like the other quadlets.
  - `latest-plus` adds server-side snapshots for bookmarks saved where SingleFile
    can't run, such as from Pinkt. linkding starts headless Chromium only for each
    snapshot job, and it exits afterwards. Check that it works without adding
    capabilities or `SecurityLabelDisable`; if Chromium needs more, record what and
    why in the quadlet. Check websvcs has about 1 GB of RAM to spare for a snapshot
    in progress.
  - Server-side snapshots fetch anonymously, so pages behind a login still need the
    browser capture below.
  - Data: `/var/opt/linkding:/etc/linkding/data` for the database on the SSD, and
    `/srv/media/archive/linkding:/etc/linkding/data/assets` so the snapshots accumulate on
    the HDD array (maintainer decision 2026-10-12).
  - Auth proxy: `LD_ENABLE_AUTH_PROXY=True`,
    `LD_AUTH_PROXY_USERNAME_HEADER=HTTP_REMOTE_USER`,
    `LD_AUTH_PROXY_LOGOUT_URL=https://dash.{{ site.url }}`,
    `LD_CSRF_TRUSTED_ORIGINS=https://archive.{{ site.url }}`. Check the names against
    linkding's `docs/src/content/docs/options.md` before writing them.
- `src/nodes/websvcs/install_svcs.sh` case `linkding`; `src/nodes/websvcs/inventory.yml` entry
  `linkding: {subdomain: archive, uptime: linkding}` (add `uptime_path` if `/` is
  not a 200 behind Authelia).
- Traefik router and service in `src/nodes/websvcs/traefik/routes.yml.j2`
  (`http://archive.{{ site.url }}:9090/`).
- Authelia: SingleFile sends `Authorization: Bearer <token>`, which Authelia's forward
  auth doesn't accept. Add a rule before the generic `*.{{ site.url }}` rules that
  bypasses `resources: ['^/api/']` on `archive.{{ site.url }}`, limited to the
  `internal` and `vpn` networks. linkding still enforces the token.
- Homepage tile under Productivity, and the install line in
  `docs/guides/websvcs.md.j2`.
- Backups: stage the SQLite database consistently in `src/nodes/websvcs/backup.sh.j2`, using
  linkding's own backup command if it has one, or `sqlite3 .backup` like
  `src/nodes/vpnsvcs/backup.sh.j2`. Decide whether snapshot files are backed up or excluded
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
    iOS fallback (share sheet to linkding, with a server-side snapshot).
  - In linkding's settings, enable automatic HTML snapshots so bookmarks added
    without SingleFile get a server-side one.
  - Android app: [Pinkt](https://github.com/fibelatti/pinboard-kotlin) from the Play
    Store, set to linkding with `https://archive.{{ site.url }}` and a REST token.
    It uses `/api/`, so it works only from the LAN or the VPN.

## Acceptance

- The render passes, and `archive.` appears in DNS, Gatus, OliveTin, sudoers and the
  dispatcher.
- Logged in through Authelia, linkding opens as the Authelia user with no second login.
- From the LAN or VPN, adding a bookmark with the linkding extension creates it with
  its tags and an HTML snapshot uploaded by SingleFile. A SingleFile upload alone
  creates the bookmark with a snapshot. From outside both networks, `/api/` is
  refused.
- A bookmark shared from Pinkt gets a server-side snapshot, and no Chromium process
  is left running afterwards.
- A backup run stages a database that opens with `sqlite3 … 'PRAGMA integrity_check'`.

## Comments

2026-10-11, implemented in the repo; acceptance needs a deploy to websvcs.

- Checked against linkding v1.47.0. The plus image runs Chromium with `--no-sandbox`,
  so the quadlet adds no capabilities. It sets `--shm-size=512m`, since Chromium
  renders through `/dev/shm` and Podman's default is 64 MB. Whether that's needed is
  unverified.
- `LD_AUTH_PROXY_LOGOUT_URL` is Authelia's `/logout`, not `dash.`: going to `dash.`
  would leave the Authelia session up.
- Backups use `dump_sqlite` (new in `backup_lib.sh`, shared with vpnsvcs) plus the data
  tree. The snapshots on the HDD array are not staged; snapraid parity is their only
  protection (maintainer decision 2026-10-12). `full_backup` was not used: it zips every
  snapshot on every run, which defeats PBS dedup.
- iOS has no Safari extension for linkding (linkding-extension#157). The reading guide
  uses linkding's "Add To Linkding" shortcut, with a server snapshot.
- Still to check on the host: Chromium memory during a snapshot, that no Chromium
  process is left over after a Pinkt save, and that `/api/` is refused from outside.
