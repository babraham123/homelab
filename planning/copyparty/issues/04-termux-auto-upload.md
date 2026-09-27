# 04. Auto-upload Car Scanner Pro exports from the phone with Termux

Status: ready-for-agent
Type: research
Repo: homelab
Source: maintainer request 2026-09-26 (https://wiki.termux.com/wiki/Intents_and_Hooks)
Blocked by: 01

## Problem

Manual uploads through the copyparty web UI work (01), but they are a chore after every
drive. Termux can run a script when a file is shared to it, or on a schedule.

## Options

1. **Share-sheet hook.** Car Scanner → Share → Termux runs
   `~/bin/termux-file-editor <path>`, which `curl`s the file to
   `https://files.SITE/car/`. One tap per trip, no background process.
2. **Scheduled folder sync.** If Car Scanner can auto-save logs to a folder:
   - `termux-setup-storage`, then a `termux-job-scheduler` job (Termux:API) that uploads
     new files from that folder and records what it has sent;
   - optionally only when on home WiFi (`termux-wifi-connectioninfo`) or while charging.

## The auth problem (main question)

Every request must pass Authelia (maintainer decision in `copyparty/spec.md`), but a
`curl` script can't complete an interactive two-factor login. Evaluate:

- **Authelia `HeaderAuthorization`** on the forward-auth endpoint
  (`server.endpoints.authz.forward-auth.authn_strategies`; confirm key names for 4.39,
  see ci-and-docs/01):
  - a dedicated LLDAP service user `car_uploader` sends basic auth;
  - an access rule allows it at `one_factor` for `files.SITE` only, ideally limited to
    the `/car` path and to `PUT`/`POST`;
  - copyparty gives that user write-only access to `/car` (no read, no delete).

  This keeps Authelia in the path, but it is a one-factor credential stored on the
  phone. Check how it interacts with auth/01's two-factor rules and Authelia's
  regulation (ban) settings.
- **Session cookie reuse.** Log in once in a browser and copy the `authelia_session`
  cookie into Termux. It expires, so this is fragile. Probably reject it.
- Record the chosen approach in `docs/security.md`, since it is a new non-interactive
  credential.

## Deliverable

- Recommendation between options 1 and 2 (depends on Car Scanner's auto-save support,
  see copyparty/02).
- The Termux script, committed under `src/copyparty/termux/` with setup steps in
  `docs/guides/`.
- The Authelia and copyparty config for the upload identity, if option A above is
  chosen.

## Comments
