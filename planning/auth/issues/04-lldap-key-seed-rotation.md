# 04. Decouple LLDAP_KEY_SEED from the admin password; document password rotation

Status: ready-for-agent
Type: research
Repo: homelab
Source: review finding 17

## Problem

`src/lldap/lldap.container.j2` binds `lldap_admin_password` to both
`LLDAP_LDAP_USER_PASS` and `LLDAP_KEY_SEED`.

## Consequences of changing the key material (answer to the maintainer's question)

LLDAP derives its server private key from `key_seed`. That key is the server side of the
OPAQUE password-authenticated key exchange: every stored user password verifier is bound
to it. **Changing the seed invalidates every user's password** — including the admin's —
and LLDAP will refuse to start against an existing database with a mismatched key
unless `force_ldap_user_pass_reset` / a reset flow is used. Rotating the admin password
today would therefore silently break login for every user. Confirm against the current
LLDAP docs for the exact behaviour of `LLDAP_KEY_SEED` / `key_file` before executing.

## Change

1. Add `lldap_key_seed` to `src/secsvcs/secrets_template.yaml` (gen: 64 alnum chars).
2. **Migration without a password reset:** set `lldap_key_seed`'s value to the *current*
   admin password string, so the derived key is unchanged. `secret_update.sh secsvcs`,
   restart lldap, confirm login. This step is a no-op cryptographically.
3. Change `Secret=lldap_admin_password,...,target=LLDAP_KEY_SEED` to
   `Secret=lldap_key_seed,...`.
4. Now rotate the admin password freely: update `lldap_admin_password` in SOPS (it is
   consumed by lldap `LLDAP_LDAP_USER_PASS` and by Authelia
   `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD`), `secret_update.sh secsvcs`, restart
   `lldap` then `authelia`.
5. Optionally later rotate the seed itself with a planned all-users password reset.

Document steps 4–5 in `docs/maintenance.md` under "Update secrets".

## Acceptance

- After step 3 all existing users still log in.
- After step 4 the old admin password no longer binds; Authelia still authenticates users.

## Comments

- 2026-09-21 maintainer: approved as written.
