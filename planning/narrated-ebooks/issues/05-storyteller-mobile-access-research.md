# 05. Research: how phones reach Storyteller, at home and away

Status: ready-for-agent
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

## Comments
