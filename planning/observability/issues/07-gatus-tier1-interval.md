# 07. Check tier-1 services every 2 minutes in Gatus

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 24

## Change

In `src/gatus/config.yaml.j2` add a third anchor:

```yaml
tier1-endpoint: &tier1
  <<: *internal
  interval: 2m
```

and apply it to: the three Traefik dashboards (`secproxy`, `homeproxy`, `webproxy`),
**`auth.SITE`** (the login portal is not monitored at all today — add
`https://auth.SITE/api/health`), `home.SITE`, `push.SITE/v1/health`, `dash.SITE`, and
`graph.SITE`. Everything else stays at `10m`.

Because the internal endpoints resolve via `1.1.1.1` and traverse HAProxy, a 2 m cadence
on ~8 endpoints is ~4 requests/min at the edge — negligible against the stick-table
thresholds (`conn_rate(3s) > 50`), but note it in the config comment.

`parse_uptime_urls.sh` keys on `group == "internal"`; the new anchor inherits that group,
so DNS generation is unaffected.

## Improvements

- Confirmed 2026-09-26: `src/gatus/config.yaml.j2` has no `auth.SITE` endpoint at all.
  Since every other endpoint's check passes through Authelia's ForwardAuth, an Authelia
  outage shows up as *every* endpoint failing; add a `[BODY].status == ok` condition on
  `/api/health` and route its failure at `severity: critical` with an inhibition rule in
  Alertmanager so the dependent endpoints are silenced while `auth` is down.
- Give the tier-1 group its own `alerting` block with a lower `failure-threshold` (2
  instead of the default) so a 2 m interval actually shortens time-to-notify.
- Add `vault.SITE/alive` to the tier-1 list once vaultwarden/01 lands (it already
  expects this).

## Comments

- 2026-09-27: restructure/01 generates the internal endpoints from
  `src/nodes.yml` (`uptime`/`uptime_path` on each service); `parse_uptime_urls.sh` is
  gone. Add a per-service attribute (e.g. `uptime_tier: 1`) and pick the anchor in the
  `src/gatus/config.yaml.j2` loop. `auth` needs `uptime` + `uptime_path: /api/health` on
  secsvcs `authelia`, which also adds it to the Gatus OIDC client's audience.
