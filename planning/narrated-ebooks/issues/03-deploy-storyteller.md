# 03. Run Storyteller on websvcs as the read-along library

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-11

## Problem

Calliope's read-along books, and any real audiobooks, need a library that serves
them to phones, with reading and listening progress synced across devices.

## Change

Follow "Add a new service" in `docs/development.md`, with Readeck
(web-archiving/02) as the model for an OIDC client on websvcs.

- `src/storyteller/storyteller.container.j2`:
  - Image: `registry.gitlab.com/storyteller-platform/storyteller`, pinned to the
    stable 2.x line (2.14.23 on 2026-10-02), not the v3 beta. Note the move to v3 as a
    follow-up once it's stable.
  - `ContainerName=storyteller`, `HostName=books.{{ site.url }}`,
    `IP={{ websvcs.container_subnet }}.20`, port 8001, `NoNewPrivileges=true`,
    `AutoUpdate=registry`. Use `.20` because copyparty/01 claims `.19`.
  - Volumes:
    - `/var/opt/storyteller:/data` for the database, uploads and Storyteller's own
      aligned books.
    - `/srv/media/books/readalouds:/library:ro` for Calliope's output.
    - Read-only is deliberate: Storyteller writes metadata edits back into files it
      imports from watched folders, and Calliope owns those files. Check that
      auto-import works read-only. If it doesn't, mount read-write and document that
      metadata edits change the files.
  - `STORYTELLER_SECRET_KEY_FILE` from a podman secret (`storyteller_secret_key` in
    `src/websvcs/secrets_template.yaml`, generated with `openssl rand -base64 32`).
    Set `PUID`/`PGID` to an owner that can read the library. Use the CPU whisper
    variant: alignment is rare here, since Calliope books are already aligned, and the
    image's CUDA 12.9 build may not run on the P4.
- **Login:**
  - Authelia OIDC client `storyteller`, with secrets in both secrets templates as
    for Readeck. `AUTH_URL=https://books.{{ site.url }}/api/v2/auth`. Register the
    callback URL Storyteller shows for the provider.
  - Map Authelia groups to Storyteller permissions, with admins in the "change server
    settings" group.
  - Keep password login on: OPDS clients and possibly the mobile apps can't use
    OAuth. Check whether the apps can, and document the result.
  - Authelia access rule: bypass `^/api/` and `^/opds/` on `books.{{ site.url }}`
    for the `internal` and `vpn` networks, like web-archiving/01. Storyteller still
    enforces its own login there.
- **Library:**
  - Add a watched folder `/library/books` for the default library.
  - Add a collection **Articles** that watches `/library/articles`, which 04 fills.
  - Configure these in `STORYTELLER_CONFIG` (JSON) if it supports watch folders and
    collections, so they live in the repo. Otherwise document them as manual steps.
- **Integration:** an `install_svcs.sh` case, a `src/nodes.yml` entry
  `storyteller: {subdomain: books, uptime: storyteller}`, a Traefik router and
  service, a Homepage tile, and the guide line.
- **Backups:** stage the SQLite database consistently with `sqlite3 .backup`. Exclude
  `/data`'s uploaded audio as large, and say so in the header comment. The
  read-along books are on the media pool.
- **Docs:** clients are the Storyteller app for Android and iOS, and Readest or
  KOReader through OPDS at `https://books.{{ site.url }}/opds/v2`, from the LAN or
  VPN.

## Acceptance

- A Calliope book in `/srv/media/books/readalouds/books/<Title>/` shows up in
  Storyteller without manual steps, and plays with highlighting in the Storyteller
  app.
- An Authelia user signs in to the web UI through OIDC, with group-mapped
  permissions.
- The OPDS feed opens in Readest from the LAN with a password login.
- A backup run stages a database that passes `PRAGMA integrity_check`.

## Comments
