# 07. Move Guacamole to a private OIDC client with code flow and PKCE

Status: ready-for-agent
Type: task
Blocked by: upstream apache/guacamole-client#1219 shipping in a Guacamole release (expected 1.7.0)
Repo: homelab
Source: maintainer request 2026-09-27; upstream GUACAMOLE-2258
(https://github.com/apache/guacamole-client/pull/1219)

## Problem

Guacamole's OpenID extension (≤ 1.6.0) only supports the implicit flow as a public client.
The Authelia client in `src/authelia/configuration.yml.j2` therefore sets `public: true`,
`grant_types: [implicit]`, `response_types: [id_token]`, `token_endpoint_auth_method: none`
and `require_pkce: false`. Implicit flow puts the ID token in the browser URL and is
deprecated in OAuth 2.1.

The first attempt, #1198, closed without being merged when the author moved branches.
#1219 continues that work and adds `openid-client-secret`, code flow, PKCE and a
well-known discovery endpoint. As of 2026-09-27 it is open with changes requested, and
the maintainer plans to release it in 1.7.0, not in 1.6.x.

## Unblock check

- #1219 (or a successor tagged GUACAMOLE-2258) is merged, **and**
- a tagged `docker.io/guacamole/guacamole` release includes it. Look for the new
  properties in the release's `guacamole-auth-sso-openid` `ConfigurationService.java`.

Before implementing, re-read the released property names. The names below come from the
PR and may change before merge.

## Change

1. **Secrets:** add `guacamole_oidc_secret` (plaintext, websvcs) and
   `guacamole_oidc_secret_hash` (secsvcs). Follow the grafana/olive_tin pattern:
   - `src/websvcs/secrets_template.yaml`: `guacamole_oidc_secret`
   - `src/secsvcs/secrets_template.yaml`: `guacamole_oidc_secret` + `guacamole_oidc_secret_hash`,
     with the `authelia crypto hash generate pbkdf2` comment
   - `planning/services-inventory/services.yml`: matching entries (`gen: *oidc_hash`,
     `remote: websvcs` for the plaintext)
2. **Authelia** (`src/authelia/authelia.container.j2`, `configuration.yml.j2`, Guacamole client):
   - `Secret=guacamole_oidc_secret_hash,type=env,target=GUAC_OIDC_HASH`
   - `client_secret: '{{ mustEnv "GUAC_OIDC_HASH" }}'` (in `{% raw %}` like the others)
   - remove `public: true` and its TODO
   - `grant_types: [authorization_code]`, `response_types: [code]`
   - `token_endpoint_auth_method`: whichever the extension sends (likely `client_secret_basic`
     or `client_secret_post`)
   - `require_pkce: true`, `pkce_challenge_method: 'S256'`
   - `access_token_signed_response_alg`: keep `none` unless the extension validates a JWT
     access token
   - add a `guacamole` entry under `claims_policies` with
     `id_token: ['email', 'groups', 'preferred_username']`, and set
     `claims_policy: 'guacamole'` on the client, like `grafana`. The extension reads the
     username and groups from the ID token. The implicit `id_token`-only flow puts scope
     claims there, but with code flow Authelia moves them to userinfo by default. Without
     this policy, `preferred_username` and `groups` drop out of the ID token and group
     permissions stop mapping.
3. **Guacamole** (`src/guacamole/guacamole.container.j2`):
   - bump `Image=` to the release that includes the PR
   - `Secret=guacamole_oidc_secret,type=env,target=OPENID_CLIENT_SECRET`
   - `OPENID_RESPONSE_TYPE=code`, `OPENID_PKCE_REQUIRED=true`
   - prefer `OPENID_WELL_KNOWN_ENDPOINT=https://auth.{{ site.url }}/.well-known/openid-configuration`
     and drop the hand-set issuer/JWKS/authorization endpoints; otherwise add
     `OPENID_TOKEN_ENDPOINT=https://auth.{{ site.url }}/api/oidc/token`
   - drop the render-time random `state` query string baked into
     `OPENID_AUTHORIZATION_ENDPOINT`. It is the same value on every login until the next
     render, so it gives no CSRF protection. Confirm the extension generates its own `state`.
     If `state` goes away, update the note in `planning/restructure/issues/01-minimal-services-inventory.md`.
4. Generate the new secrets, deploy, then run `install_authelia` and `install_guacamole`.

## Acceptance

- Logging in at `remote.<site>` redirects to Authelia with `response_type=code`,
  `code_challenge_method=S256` and a `state` that changes on each login.
- Authelia logs show a token-endpoint exchange authenticated with the client secret. The
  browser URL never contains an `id_token`.
- Authelia rejects a login attempt without PKCE, or with the client set back to `public`.
- The decoded ID token contains `preferred_username` and `groups`. Group-based
  permissions (`OPENID_GROUPS_CLAIM_TYPE=groups`) still map as before, e.g. a member of
  a database user group with `ADMINISTER` still sees Settings → Connections.
- No `grant_types: implicit` client remains in `configuration.yml.j2`.

## Comments
