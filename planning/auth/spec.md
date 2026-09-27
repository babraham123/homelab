# Authorization model

Authelia currently gates every subdomain with one group and downgrades everything to
one factor on the LAN/mesh. Introduce an admin group, group-based gating for telemetry
tools, and fix the LLDAP key-seed coupling.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-admin-two-factor.md) | Require two_factor for admin subdomains from every network | `ready-for-agent` | task |
| [02](issues/02-telemetry-group-gating.md) | Gate VictoriaMetrics/VictoriaLogs/Alertmanager/ntfy UIs on a telemetry LDAP group | `ready-for-agent` | task |
| [03](issues/03-haproxy-hardening-todo.md) | Add a TODO block to haproxy.cfg for auth-portal rate limiting and other hardening | `ready-for-agent` | task |
| [04](issues/04-lldap-key-seed-rotation.md) | Decouple LLDAP_KEY_SEED from the admin password; document password rotation | `ready-for-agent` | research |
| [05](issues/05-olivetin-oidc-groups.md) | Test OliveTin OIDC group claims and drop the allow-everyone workaround | `ready-for-human` | task |
| [06](issues/06-real-client-ip.md) | Verify the real client IP reaches Traefik and apps through HAProxy | `ready-for-agent` | task |
| [07](issues/07-guacamole-private-client.md) | Move Guacamole to a private OIDC client with code flow and PKCE | `ready-for-agent` | task |
