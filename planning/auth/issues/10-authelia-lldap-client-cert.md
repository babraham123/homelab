# 10. Give Authelia a real client cert for LLDAP, and make LLDAP verify it (or drop it)

Status: resolved
Type: task
Repo: homelab
Source: maintainer request 2026-10-11; `docs/security.md` Known gaps ("LLDAP doesn't verify
  Authelia's client cert either")

## Problem

Authelia's LDAPS connection to LLDAP is configured to present a client certificate, but the cert is
wrong and nothing checks it:

- **Wrong cert.** `src/services/authelia/authelia.container.j2` sets
  `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_TLS_{PRIVATE_KEY,CERTIFICATE_CHAIN}_FILE` to
  `/certificates/auth.{key,cert.pem}`. That is Authelia's **server** cert:
  `src/base/certificates/self_signed_cert_gen.sh.j2` signs `auth.SITE` with `-extensions server_cert`,
  which `openssl.intermediate.cnf.j2` defines as `extendedKeyUsage = serverAuth` only. A verifying
  server would reject it as a client cert. The same pair is reused for the SMTP notifier
  (`AUTHELIA_NOTIFIER_SMTP_TLS_*`).
- **Never verified.** `[ldaps_options]` in `src/services/lldap/lldap_config.toml.j2` has only
  `enabled`, `port`, `cert_file`, `key_file`; there is no client CA or require-client-cert setting,
  so LLDAP accepts any client that completes the TLS handshake. Authentication is the bind password
  (`lldap_admin_password`) alone.

The result is config that looks like mutual TLS and isn't, which `docs/security.md` lists as a known
gap.

## Change

1. **Check upstream.** Confirm in lldap's source/docs (`lldap/lldap`, `server/src/infra/ldap_server.rs`
   and the config reference) whether any released version can require and verify client certs. Record
   the answer (version, option names, or "unsupported" + issue link) under `## Comments`.
2. **If LLDAP supports it:**
   - issue `auth.SITE.client_cert.pem` with `-extensions usr_cert` in
     `self_signed_cert_gen.sh.j2`, add it to the chain bundle list, and ship it through
     `install_certs` in `src/nodes/secsvcs/commands.sh.j2` (same pattern as
     `secproxy.SITE.client_cert.pem`);
   - point the two LDAP env vars in `authelia.container.j2` at the client cert (key stays
     `auth.key`, as the proxies reuse their server key); leave SMTP on whatever its server accepts;
   - set LLDAP's client CA to `/data/certificates/ca.chain.pem` (already installed) and require a
     client cert on 6360.
3. **If LLDAP doesn't support it:** delete the two `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_TLS_*`
   env vars so the config stops implying mTLS, and keep the transport protection to server-verified
   LDAPS + the bind password. Optionally open/link an upstream feature request.
4. Update `docs/security.md` (Known gaps, Internal TLS bullet) to match the outcome.

## Acceptance

- Authelia logs in a user against LLDAP after `install_certs` + restart on secsvcs.
- Supported case: `openssl s_client -connect ldap.SITE:6360` **without** a client cert fails the
  handshake; with `auth.SITE.client_cert.pem` + key it succeeds. Unsupported case: no client-cert
  env vars remain for the LDAP backend.
- `docs/security.md` no longer lists an Authelia↔LLDAP client-cert gap, or states the remaining gap
  accurately.

## Comments

### 2026-10-11: step 1 answer, unsupported

LLDAP can't verify client certs as of v0.6.3 (`main` pushed 2026-09-26). `get_tls_acceptor` in
`server/src/ldap_server.rs` builds the rustls `ServerConfig` with a hardcoded
`.with_no_client_auth()`, and `LdapsOptions` in `server/src/configuration.rs` has only `enabled`,
`port`, `cert_file`, `key_file`. No upstream issue or PR asks for client-cert auth (searched
"client certificate", "mTLS"). Take step 3; an upstream feature request is the optional part.

### 2026-10-11: resolved, unsupported branch

Removed the two `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_TLS_*` env vars from `authelia.container.j2`;
`docs/security.md` Known gaps now states the Authelia→LLDAP gap as it is. The SMTP notifier's
`auth.key`/`auth.cert.pem` pair is untouched. Upstream feature request:
[lldap/lldap#1526](https://github.com/lldap/lldap/issues/1526). Host check (Authelia logs in
against LLDAP) is part of `install_authelia` in the apply notes.
