# 13. Alert on log lines through a second vmalert backed by VictoriaLogs

Status: needs-triage
Type: task
Repo: homelab
Source: vaultwarden/01 (2026-10-12)

## Problem

vmalert's only datasource is VictoriaMetrics, so no rule can fire on a log line. The first one
wanted is Vaultwarden's `Invalid admin token. IP: <ip>` (`src/services/vaultwarden`). It is
reachable only after Authelia, so any hit means a signed-in user is guessing the admin token.
Failed SSO logins happen in Authelia and are already covered by the `auth` group in
`src/services/vmalert/configs/homelab.yml`.

## Change

- A second vmalert on secsvcs with `-datasource.url` pointing at VictoriaLogs and
  `-rule.defaultRuleType=vlogs`, sending to the same Alertmanager.
- A rule matching `Invalid admin token` in the `vaultwarden` unit's logs over a few minutes,
  labelled with the IP from the line.

## Acceptance

- A wrong admin token at `https://vault.SITE/admin` fires the alert and reaches ntfy.
