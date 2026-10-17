# 04. Decouple LLDAP_KEY_SEED from the admin password; document password rotation

Status: ready-for-human
Type: research
Repo: homelab
Source: review finding 17

## Problem

`src/services/lldap/lldap.container.j2` binds `lldap_admin_password` to both `LLDAP_LDAP_USER_PASS`
and `LLDAP_KEY_SEED`.

## Consequences of changing the key material (answer to the maintainer's question)

LLDAP derives its server private key from `key_seed`. That key is the server side of the OPAQUE
password-authenticated key exchange: every stored user password verifier is bound to it. **Changing
the seed invalidates every user's password**, the admin's included. LLDAP stores a hash of the key
in its database and refuses to start when the key differs ("The private key encoding the passwords
has changed since last successful startup"), unless started once with
`LLDAP_FORCE_UPDATE_PRIVATE_KEY=true` (`server/src/main.rs`, checked 2026-10-12). Rotating the
admin password while it was also the seed would therefore have stopped LLDAP from starting, and
forcing past that would have broken login for every user.

## Change

1. Add `lldap_key_seed` to `src/nodes/secsvcs/secrets_template.yaml` (gen: 64 alnum chars).
2. **Migration without a password reset:** set `lldap_key_seed`'s value to the *current* admin
   password string, so the derived key is unchanged. `secret_update.sh secsvcs`, restart lldap,
   confirm login. This step is a no-op cryptographically.
3. Change `Secret=lldap_admin_password,...,target=LLDAP_KEY_SEED` to `Secret=lldap_key_seed,...`.
4. Now rotate the admin password freely: update `lldap_admin_password` in SOPS (it is consumed by
   lldap `LLDAP_LDAP_USER_PASS` and by Authelia `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD`),
   `secret_update.sh secsvcs`, restart `lldap` then `authelia`.
5. Optionally later rotate the seed itself with a planned all-users password reset.

Document steps 4–5 in `docs/maintenance.md` under "Update secrets".

## Acceptance

- After step 3 all existing users still log in.
- After step 4 the old admin password no longer binds; Authelia still authenticates users.

## Comments

- 2026-09-21 maintainer: approved as written.
- 2026-10-12 agent: repo side done (steps 1 and 3). `lldap_key_seed` is in the secsvcs secrets
  template and the LLDAP quadlet binds it to `LLDAP_KEY_SEED`. Step 4 needs no LLDAP flag:
  `force_ldap_user_pass_reset = "always"` already resets the admin to `lldap_admin_password` on
  every start. Step 5, if ever: set a new seed, start LLDAP once with
  `LLDAP_FORCE_UPDATE_PRIVATE_KEY=true` and `LLDAP_FORCE_LDAP_USER_PASS_RESET=true` (it updates the
  stored key hash, then exits on purpose), start it again without them, and every user resets their
  password.
- 2026-10-12 maintainer: the rotation steps stay out of `docs/maintenance.md`. The migration (step 2
  before installing the new quadlet, then step 4 and the acceptance checks) is in the apply notes
  (`notes/apply-since-5a50097.md`, steps 0 and 8). If the quadlet lands first, LLDAP fails to
  start on the key-hash check; nothing is lost, set the secret and restart.
