# 06. Add the cert-expiry vmalert rules the docs already claim exist

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 23
Blocked by: 01

## Problem

`docs/security.md#tls-and-trust-hierarchy` says "Gatus and vmalert also alert on
approaching expiry." vmalert has no such rule.

## Change

No new exporter needed: Gatus already exports certificate expiry for every endpoint it
checks. In `src/vmalert/configs/homelab.yml` (observability/01):

```yaml
- alert: CertExpiringSoon
  expr: gatus_results_certificate_expiration_seconds < 14 * 86400
  for: 1h
  labels: {severity: warning}
  annotations:
    summary: "{{ $labels.name }} certificate expires in {{ $value | humanizeDuration }}"
- alert: CertExpiringCritical
  expr: gatus_results_certificate_expiration_seconds < 3 * 86400
  labels: {severity: critical}
```

Verify the metric name against `uptime.SITE:8080/metrics` (Gatus renamed some metrics
across versions). Internal-CA certs (LDAPS, Postgres, MQTT) are not HTTP endpoints Gatus
sees; for those either add Gatus TCP+TLS endpoints (`tls://pgdb.SITE:5432` style checks
support `[CERTIFICATE_EXPIRATION]`) or leave them to `cert_notifier` and say so in the
doc.

Update `docs/security.md` to describe the actual three paths (Gatus condition,
vmalert-on-Gatus-metric, `cert_notifier` email) accurately.

## Comments
