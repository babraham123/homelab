# 03. Run Storyteller on websvcs as the read-along library

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-11

## Problem

Calliope's read-along books, and any real audiobooks, need a library that serves
them to phones, with reading and listening progress synced across devices.

## Change

Follow "Add a new service" in `docs/development.md`, with Readeck
(web-archiving/02) as the model for an OIDC client on websvcs.

- `src/services/storyteller/storyteller.container.j2`:
  - Image: `registry.gitlab.com/storyteller-platform/storyteller`, pinned to the
    stable 2.x line (2.14.23 on 2026-10-02), not the v3 beta. Note the move to v3 as a
    follow-up once it's stable.
  - `ContainerName=storyteller`, `HostName=books.{{ site.url }}`,
    `IP={{ websvcs.container_subnet }}.21`, port 8001, `NoNewPrivileges=true`,
    `AutoUpdate=local`. Use `.21`: copyparty/01 claims `.19` and fluentbit has
    `.20`.
  - Volumes:
    - `/var/opt/storyteller:/data` for the database, uploads and Storyteller's own
      aligned books.
    - `/srv/media/books/readalouds:/library` for Calliope's output, read-write for
      now. Storyteller writes metadata edits back into files it imports from watched
      folders, so document that editing a book in Storyteller changes Calliope's
      output, and that re-running Calliope on a book overwrites those edits.
  - `STORYTELLER_SECRET_KEY_FILE` from a podman secret (`storyteller_secret_key` in
    `src/nodes/websvcs/secrets_template.yaml`, generated with `openssl rand -base64 32`).
    Set `PUID`/`PGID` to an owner that can read the library. Use the CPU whisper
    variant: alignment is rare here, since Calliope books are already aligned, and the
    image's CUDA 12.9 build may not run on the P4.
- **Login:**
  - Authelia OIDC client `storyteller`, with secrets in both secrets templates as
    for Readeck. `AUTH_URL=https://books.{{ site.url }}/api/v2/auth`. Register the
    callback URL Storyteller shows for the provider.
  - Map Authelia groups to Storyteller permissions, with admins in the "change server
    settings" group.
  - Keep password login on: OPDS clients can't use OAuth, and the mobile apps may
    not either. 05 researches mobile access.
  - Authelia access rule: bypass `^/api/` and `^/opds/` on `books.{{ site.url }}`
    for the `internal` and `vpn` networks, like web-archiving/01. Storyteller still
    enforces its own login there.
- **Library:**
  - Add a watched folder `/library/books` for the default library.
  - Add a collection **Articles** that watches `/library/articles`, which 04 fills.
  - Configure these in `STORYTELLER_CONFIG` (JSON) if it supports watch folders and
    collections, so they live in the repo. Otherwise document them as manual steps.
- **Integration:** an `install_svcs.sh` case, a `src/nodes/websvcs/inventory.yml` entry
  `storyteller: {subdomain: books, uptime: storyteller}`, a Traefik router and
  service, a Homepage tile, and the guide line.
- **Backups:** stage the SQLite database consistently with `sqlite3 .backup`. Exclude
  `/data`'s uploaded audio as large, and say so in the header comment. The
  read-along books are on the media pool.
- **Docs:** clients are the Storyteller app for Android and iOS, and Readest or
  KOReader through OPDS at `https://books.{{ site.url }}/opds/v2`, from the LAN or
  VPN. 05 settles how phones reach it away from home.

## Acceptance

- A Calliope book in `/srv/media/books/readalouds/books/<Title>/` shows up in
  Storyteller without manual steps, and plays with highlighting in the Storyteller
  app.
- An Authelia user signs in to the web UI through OIDC, with group-mapped
  permissions.
- The OPDS feed opens in Readest from the LAN with a password login.
- A backup run stages a database that passes `PRAGMA integrity_check`.

## Comments

2026-10-11, implemented in the repo; acceptance needs a deploy to websvcs.
- Checked against `web-v2.14.23`.
  - The image tag is `web-v2`, which follows stable 2.x only; it is the CPU build. The
    CUDA builds are 11.8, 12.9 and 13.1.
  - The IP is `.21`, since fluentbit has `.20`.
  - The uptime check is `/api/health`, which needs no auth.
- `STORYTELLER_CONFIG` (`src/services/storyteller/config.json.j2`) holds the Authelia provider,
  `opdsEnabled` and `webUrl`. It reads the client id and secret from mounted podman
  secrets through `clientId_file` and `clientSecret_file`.
  - `groupPermissions` gives `storyteller_admin` everything and `authelia_gen_access`
    read, download and list.
  - Storyteller sets permissions only at a user's first sign-in.
- Watch folders and the Articles collection are manual steps in the guide. The config
  file can't assign a rule to a collection, and rules defined there are locked in the
  UI.
- `disablePasswordLogin` only hides the form: the token endpoint and OPDS Basic auth
  still accept passwords, and there's no rate limiting. That's why `/api/` and `/opds`
  are bypassed only for the LAN and VPN (see 05).
- The library is mounted read-write. The install case and Calliope give it to
  1000:1000, Storyteller's default PUID:PGID.
