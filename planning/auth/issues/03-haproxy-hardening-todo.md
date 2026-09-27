# 03. Add a TODO block to haproxy.cfg for auth-portal rate limiting and other hardening

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 14 (user chose a HAProxy TODO over tightening Authelia regulation)

## Change

Add a commented `# TODO` block at the top of `src/haproxy/haproxy.cfg.j2` listing:

- Per-SNI stricter limits for `auth.SITE` (the only brute-forceable surface): a
  dedicated stick table keyed on `src` for connections where `req.ssl_sni -i auth.SITE`,
  with a much lower `conn_rate` threshold and a long `expire`.
- A sticky-ban `gpc0` on the `https_all` frontend (only the `:80` frontend has one).
- Raise `stick-table ... expire 30s` on `https_all`; 30 s means a scanner is forgotten
  almost immediately.
- Note the interaction with Authelia's own `regulation` block
  (`max_retries: 3 / find_time: 2m / ban_time: 5m`), which stays as is per maintainer
  decision.

Also record the same TODO in `docs/security.md#the-edge-haproxy` so it isn't only in a
config comment.

## Comments
