# 10. Validate the alerting pipeline end to end

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-09-26

## Problem

Nothing proves an alert reaches the phone. The path has five hops and two email side
channels, and some config looks wrong on reading:

```
vmalert --notifier.url--> alertmanager (alert.SITE:9093, basic auth)
  ├─ email_configs --> smtp-relay.gmail.com --> <email>+alert@
  └─ webhook --> ntfy-alertmanager (:2588, basic auth)
        ├─ ntfy topic "alert" (user alert) --> ntfy (push.SITE, :2586) --> phone app
        │     (iOS instant push via upstream-base-url https://ntfy.sh)
        └─ email-address <email>+alert2@
```

Every rule in observability/01 and /06, the image updater's alerts and the backup
staleness alerts depend on this path.

## Defects (confirmed in the tree 2026-09-26; fix before the test plan)

1. **Missing ports.**
   - `src/alertmanager/config.yml.j2.j2:83` webhook is `http://ntfy-alertmanager.{{ site.url }}`,
     but ntfy-alertmanager listens on `:2588` (`ntfy-alertmanager.scfg.j2.j2:8`).
   - `src/alertmanager/ntfy-alertmanager.scfg.j2.j2:68` topic is
     `http://push.{{ site.url }}/alert`, but ntfy listens on `:2586` (`ntfy/config.yml.j2.j2:24`).

   vmalert's URLs all carry explicit container ports (`:8428`, `:9093`). Whichever way
   the name resolves, port 80 is wrong: Podman's DNS returns the container IP (nothing
   listens on 80), and the site DNS returns Traefik, whose `web` entrypoint answers with
   a redirect to HTTPS that the webhook then follows into the `authelia`-less
   `ntfy-alertmanager` router with a `Basic` header meant for the container, not Traefik.
   Fix: `http://ntfy-alertmanager.{{ site.url }}:2588/` and
   `http://push.{{ site.url }}:2586/alert`, matching the vmalert convention.
   Confirm with `podman logs alertmanager` before and after.
2. **Typo.** `ntfy-alertmanager.scfg.j2.j2:45` `instance "sevsvcs.{{ site.url }}"` should be
   `secsvcs`.
3. **Instance tags never match.** Instance labels carry a port (the relabel in
   `src/secsvcs/prometheus.yml.j2:50` sets `secsvcs.{{ site.url }}:9100`), while the scfg
   matches bare hostnames. ntfy-alertmanager matches label values exactly. Preferred fix:
   in every `prometheus.yml.j2` relabel a separate `host` label (`secsvcs.SITE`, no
   port) and match on that in the scfg, so the same tag block works for node_exporter,
   Traefik (observability/03) and HAProxy (observability/04) targets on the same host.

## Improvements while in there

- Add `amtool check-config` and `ntfy-alertmanager --config ... --check` (if it has one;
  otherwise a dry start) to the pre-install checks in ci-and-docs/02, so a port or
  hostname regression fails the install, not the next alert.
- Put the resolved URL scheme in a comment at the top of both files: "container-to-
  container, always `<hostname>.SITE:<container port>`, never through Traefik".
- Keep test 2's `pipeline_test.yml` rule permanently as `Watchdog` (see the dead-man
  section), so the end-to-end path is exercised every evaluation interval rather than
  once a quarter.

## Test plan

Run each step and record the result under `## Answer`.

| # | Test | How | Expect |
|---|---|---|---|
| 1 | Alertmanager → ntfy, isolated | `amtool alert add PipelineTest severity=warning instance=test --alertmanager.url=https://alert.SITE` (basic auth), or POST `/api/v2/alerts` | ntfy notification priority 3, tag `warning`; email to `+alert@` and `+alert2@` |
| 2 | Full path from vmalert | temporary `src/vmalert/configs/pipeline_test.yml`: `alert: PipelineTest, expr: vector(1), labels: {severity: critical}` | ntfy priority 5, `rotating_light`, within `group_wait` (30 s) + eval interval |
| 3 | Severity map | repeat 1 for `error`, `info` | priorities 4 and 1 |
| 4 | Inhibition | fire `critical` and `warning` with the same `alertname` and `instance` | only the critical one is delivered |
| 5 | Resolve | delete the test rule / let the amtool alert expire | ntfy `resolved,tada` priority 1; resolved email |
| 6 | Silence button | tap the ntfy action | Alertmanager shows a 24 h silence; no repeat |
| 7 | Phone off-LAN | repeat 1 with the phone on mobile data | notification arrives (iOS via upstream ntfy.sh) |
| 8 | ntfy down | `systemctl stop ntfy`, repeat 1 | both emails still arrive; ntfy-alertmanager logs the failure |
| 9 | ntfy-alertmanager down | stop it, repeat 1 | `+alert@` email still arrives |
| 10 | Alertmanager down | `systemctl stop alertmanager` | VPS dead-man: email + ntfy.sh push within 15 min; recovery notice after restart. (Today nothing notifies: Gatus's `EndpointDown` also routes through Alertmanager) |
| 11 | secsvcs down | shut down the secsvcs VM | VPS dead-man fires the same way |

Remove `pipeline_test.yml` afterwards, or keep it disabled behind a comment for the next
run.

## Dead-man switch (on the VPS — maintainer decision)

The whole path runs on secsvcs, so it cannot report its own death: secsvcs down,
Alertmanager down, or email and ntfy both broken. The VPS is off-site, always on and
reachable over the tailnet, so it watches from outside.

- **Watchdog rule:** `src/vmalert/configs/pipeline.yml`: `alert: Watchdog`, `expr: vector(1)`,
  `labels: {severity: none}`. Route it in Alertmanager to a `null` receiver so it never
  notifies. It only needs to be *present* in Alertmanager.
- **VPS checker (pull, not push):** `src/vpn/deadman.sh` + `deadman.{service,timer}`
  (every 5 min), a new `deadman` case in `src/vpn/install_svcs.sh.j2`.
  - Over the tailnet:
    - `GET https://alert.{{ site.url }}/api/v2/alerts?filter=alertname="Watchdog"`
      (basic auth). This proves vmalert → Alertmanager is alive and evaluating.
    - `GET https://push.{{ site.url }}/v1/health`. This proves ntfy is up.
  - Pull keeps the VPS free of a new listener; HAProxy stays its only public surface.
  - Fire after **3 consecutive failures** (15 min) to ride out restarts and deploys.
    Notify once on fire and once on recovery. Keep state in `/var/lib/deadman/`.
- **Notification independent of secsvcs:**
  - email via `smtp-relay.gmail.com` (`msmtp`, same account as Alertmanager's
    `alert_smtp_password`);
  - **and** a push to a random, unguessable topic on public `ntfy.sh`, which the phone
    app also subscribes to.

  Credentials go in `/etc/opt/secrets/` on the VPS, the pattern
  `install_svcs.sh.j2 headscale` already uses. Message says which check failed
  (Alertmanager unreachable / Watchdog missing / ntfy down / tailnet down).
- If the VPS itself or its tailnet link dies, the checker can't tell, so the check must
  fail *closed*: any error counts as a failure. The mirror image, VPS down, is covered by
  observability/01 `NodeDown` on the vpn node's node_exporter (via observability/04 or 08).

## Also

- Write the test plan into `docs/maintenance.md` as a quarterly check, next to the
  restore test (backup-and-dr/06).
- `docs/services.md` / `docs/security.md`: describe the actual notification paths.

## Acceptance

- Tests 1–9 pass. Tests 10 and 11 are caught by the VPS dead-man switch within 15 min.
- The suspected defects are either fixed or confirmed harmless, with the reason.

## Comments
