# 01. Run copyparty on websvcs behind Authelia

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-09-26; `notes/TODO.md` "setup copyparty"
Blocked by: auth/06

## Problem

There's nowhere on the network to drop files from the phone. Car Scanner Pro logs need
a landing directory the sync (03) can read.

## Change

- `src/copyparty/copyparty.container.j2`, following `src/archivebox/archivebox.container.j2`:
  `Image=docker.io/copyparty/ac:latest`, `ContainerName=copyparty`,
  `HostName=files.{{ site.url }}`, `IP={{ websvcs.container_subnet }}.19` (next free;
  `.18` is taken), port 3923, `NoNewPrivileges=true`.
  - Bind mounts: `/etc/opt/copyparty:/cfg:ro`, `/var/opt/copyparty/data:/w`. Use a host
    path rather than a named volume so 02 can read uploads from the host.
  - `AutoUpdate=registry` for now to match the other quadlets. image-updater/05 converts
    it with the rest.
- `src/copyparty/copyparty.conf.j2`:
  - Trust Authelia's identity header: `idp-h-usr: Remote-User`,
    `idp-h-grp: Remote-Groups`, `xff-src: {{ websvcs.container_subnet }}.6` (Traefik
    only), `rproxy: 1`.
  - Volume `/car` → `/w/car`, read-write for the maintainer's user. Optionally add a
    `/drop` volume that is upload-only (`w` without `r`) for general use.
  - Before writing these keys, check the exact names against the copyparty README
    (IdP section, `--idp-h-usr`, volume flags).
- `src/websvcs/traefik/routes.yml.j2`: router `files` (`Host(files.SITE)`, the `*service`
  anchor with `authelia@file`) and service `http://files.{{ site.url }}:3923/`.
  - **Public, authenticated (maintainer decision).** websvcs is HAProxy's catch-all
    backend (`use_backend websvcs_https_proxy if tld || any_subdomain`), so `files.SITE`
    is reachable from the internet. That is accepted, provided `authelia@file` is on
    the router and no path bypasses it. Don't add an Authelia `bypass` rule for
    `files.SITE`, and don't add a Traefik router for it without the middleware.
  - **Client IP check:** auth/06. Set `xff-src` to Traefik's IP only.
- `src/websvcs/install_svcs.sh copyparty` case: create `/var/opt/copyparty/data/car`
  (owned by the container UID), copy config and quadlet, restart. Add it to
  `install_all_svcs` and regenerate the websvcs dispatcher.
- `docs/services.md` websvcs table row (`.19 | copyparty | copyparty | File drop (behind Authelia) |
  files.SITE`), Homepage entry, Gatus internal endpoint (10m tier).
- `/var/opt/copyparty/data` is covered by the websvcs VM backup (backup-and-dr/01). Note
  this in the backup-and-dr/09 inventory if 01 hasn't landed yet.

## Acceptance

- From the phone on home WiFi and on mobile data: log in through Authelia, upload a
  file to `/car`, and it appears at `/var/opt/copyparty/data/car/` on websvcs.
- Unauthenticated requests from the internet (browser and `curl`, including WebDAV
  paths) are redirected to Authelia or get 401; none reach copyparty.
- Logs show the real client IP for external requests.
- A user without access to `/car` can't list it.

## Comments
