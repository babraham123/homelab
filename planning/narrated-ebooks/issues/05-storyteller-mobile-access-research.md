# 05. Research: how phones reach Storyteller, at home and away

Status: resolved
Type: research
Repo: homelab
Source: maintainer request 2026-10-11
Blocked by: 03

## Problem

03 serves Storyteller at `books.{{ site.url }}` behind Authelia, with `^/api/` and
`^/opds/` bypassed only for the `internal` and `vpn` networks. Its docs don't say
whether the Storyteller apps for Android and iOS can sign in through Authelia, or
which paths they call. So it's unknown whether the apps work away from home without
the tailnet, and what has to be opened for them.

## Questions to answer

1. **App login.** Can the Storyteller apps (stable 2.x) sign in through the server's
   OIDC provider, or only with a username and password? Does v3 change that? Check
   the app source and release notes, and try it against 03's deployment.
2. **Paths.** Which paths do the apps call: `/api/v2/...`, downloads, audio
   streaming, cover images, progress sync? Capture them from the Traefik access log
   during a sign-in, a download and a listening session.
3. **Away from home.** Compare, for Android and iOS:
   - the tailnet always on (headscale, ADR 0003), keeping the bypass limited to
     `internal` and `vpn`;
   - the app's paths bypassed for every network, relying on Storyteller's own login,
     with brute-force limits (Authelia's regulation doesn't apply to bypassed paths;
     check Storyteller and Traefik rate limits);
   - Authelia `one_factor` or `two_factor` on those paths, if the apps can carry the
     session cookie at all.
4. **Offline.** Do downloaded read-along books play with highlighting offline, and
   does progress sync catch up when the phone reconnects?
5. **OPDS clients.** Do Readest and KOReader on a phone reach `/opds/v2` with a
   password away from home under the chosen option?

## Output

A recommendation with the evidence above, added as a comment here. Then either a
follow-up `task` ticket with the Authelia rule, Traefik and docs changes, or a note
in 03's docs that the tailnet is required away from home.

## Answer

2026-10-11, from Storyteller's source at `web-v2.14.23`, `mobile-v2.11.7` and
`web-v3.0.0-beta.48`. Nothing was captured from a live deployment; the unverified
items are listed below.

**Recommendation: keep the bypass to `internal` and `vpn`, and require the tailnet
away from home.** `docs/guides/reading.md` says so. No follow-up task is needed.

1. **App login:** the apps can use OIDC. They have no password form. The login
   button opens `/api/v2/token/app` in a system browser auth session. That redirects
   to `/login`, where Authelia and Storyteller's password and OIDC buttons apply. It
   then returns `storyteller://…?token=` and the app exchanges it for a long-lived
   session token. A QR device-code flow (`/device/start`) is the alternative. v3 beta
   uses the same app and flow.
2. **Paths:** after login, every call is native and carries
   `Authorization: Bearer <session token>`, with no proxy cookie:
   - `/api/v2/books`, `/books/{id}`, `/books/{id}/files?format=…`, `/books/{id}/cover`
   - `/books/{id}/positions`, `/books/{id}/status`, `/statuses`
   - `/user`, `/token/app`, `/device/token`
   
   So Authelia can never sit in front of `/api/`. The apps support no custom headers or
   mTLS.
3. **Away from home:**
   - **Tailnet always on:** works today and keeps Storyteller's API off the internet.
     Chosen.
   - **Bypass for every network:** rejected.
     - Storyteller has no rate limiting or lockout on any password endpoint: the
       Auth.js credentials callback, `POST /api/v2/token` and OPDS Basic auth.
     - `disablePasswordLogin` only hides the form.
     - Authelia's regulation doesn't apply to bypassed paths.
   - **Authelia in front of the API:** impossible, per 2.
4. **Offline:** downloaded books play from local files. Positions are stored locally
   and pushed every 3 s while the app is in the foreground; the server's newer position
   wins (409). The docs say downloads can be read offline.
5. **OPDS:** Readest and KOReader use Basic auth with a local account, so they also
   need the tailnet away from home. Thorium could use Storyteller's OPDS
   authentication flow, but that changes nothing about the network exposure.

Unverified, check when 03 is deployed: highlighting while offline, and whether the
iOS and Android auth session reuses the browser's Authelia cookie (if not, it is one
extra Authelia login per app sign-in, which is harmless).
