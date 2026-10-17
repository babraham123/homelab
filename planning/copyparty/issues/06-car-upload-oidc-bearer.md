# 06. OIDC client and bearer-token uploads for the WiCAN sync app

Status: needs-triage
Type: task
Repo: homelab
Source: wican1 session 2026-10-14
Blocked by: the app's OIDC milestone (its repo's `planning/`)

## Problem

The WiCAN sync app (05) first uploads with Basic auth as `car_uploader`: a long-lived password
stored on the phone, one factor. Authelia 4.39 supports the device authorization grant and bearer
tokens on forward-auth, so the app can get revocable tokens tied to a real login instead.

## Change

- Authelia OIDC client for the app in `src/services/authelia/configuration.yml.j2`
  (`identity_providers.oidc.clients`):
  - public client (no secret);
  - grant types: device authorization (`urn:ietf:params:oauth:grant-type:device_code`) and
    `refresh_token`;
  - scopes: `offline_access`, `authelia.bearer.authz`;
  - `audience`: `https://files.{{ site.url }}`, which bearer authz requires.
- The `^/car/` `PUT`/`POST` rule for `files.{{ site.url }}` accepts the app's bearer tokens
  alongside the existing one_factor `user:car_uploader` subject, e.g. a second subject
  `oauth2:client:<client_id>`. Check in the 4.39 docs whether a user-delegated token matches the
  user subject or the client subject.
- No forward-auth change: `HeaderAuthorization` already allows `Bearer` (`server.endpoints.authz`).
- `docs/security.md`: record the client, its scope, and how to revoke a phone's tokens.
- Once the app runs on bearer tokens, remove the Basic path and `car_uploader`, or keep them as a
  fallback. Decide when this lands.

## Acceptance

- The app logs in by device code and uploads to `/car/` with a bearer token.
- The token is refused anywhere except `PUT`/`POST` on `files.SITE/car/`.
- Revoking the token stops uploads.

## Comments
