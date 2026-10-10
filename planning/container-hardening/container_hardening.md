# Container hardening

Per-container survey of `DropCapability`/`AddCapability`, `ReadOnly`, `Tmpfs`, `UserNS=auto`
and `HealthCmd` for every quadlet, with the directive block to paste into each
`src/**/*.container.j2`. Answers [01](issues/01-capabilities-readonly-tmpfs-survey.md)
and [02](issues/02-healthcmd-survey.md).

## Scope and method

- **Rootful stays.** Rootless is out (maintainer decision: it would replace the static-IP
  bridge model). `UserNS=auto` is the rootful substitute for "root inside ≠ root on the VM".
- **Inventory.** 34 quadlet templates (`find src -name '*.container*'`), not 31: the three
  Traefik templates (secsvcs, homesvcs, websvcs) share one image, and `geoip_generator`
  (vpnsvcs, a timer-run job) was added after this survey and isn't covered. `fluentbit` runs on
  4 nodes and `vmagent` on 3 from one template each. `vault` has no quadlet. The wyoming
  trio is commented out of `src/nodes/websvcs/install_svcs.sh` (not in use). Every `Image=` is pinned in the quadlet itself, not in
  `vars.template.yml`; most tags float (`latest`, `stable`, `release`) under
  `AutoUpdate=registry`, so the resolved versions below are a snapshot of 2026-10-10 and
  can drift.
- **Podman version.** The nodes run Podman **5.8.2**. Every directive used here
  (`DropCapability`, `AddCapability`, `ReadOnly`, `ReadOnlyTmpfs`, `Tmpfs`, `UserNS`,
  `HealthCmd`, `HealthInterval`, `HealthRetries`, `HealthOnFailure`, `HealthStartPeriod`) is in
  the [v5.8.2 quadlet key table][psu].
- **Method.** Nothing was run on a node. Each claim comes from one of: the image config blob
  for the pinned tag, fetched from the registry HTTP API (`User`, `Entrypoint`, `Cmd`,
  `Healthcheck`, build history); a file listing of every layer of that image (whiteouts
  applied) for `curl`/`wget`/`nc`/interpreters; the upstream Dockerfile and entrypoint at the
  matching tag or commit; upstream docs. Sources are cited per container and listed at the end.
- **Every block is source-derived, not tested.** Treat each as the starting point for the
  loop below, not a final answer.
- **Health checks only on core services**: identity (lldap, authelia), ingress (traefik),
  the database (postgres), the telemetry and alerting stack (victoriametrics, vmagent,
  vmalert, alertmanager, ntfy-alertmanager, ntfy, grafana) and the MQTT broker (mosquitto).
  victorialogs, gatus and fluentbit are core too, but their images have no shell or client;
  `up` covers them. Every other service gets caps and `ReadOnly` only, with a candidate check
  noted in case it's wanted later.

### Semantics that shape every block

- `ReadOnly=true` with the default `ReadOnlyTmpfs=true` already mounts read-write tmpfs on
  `/dev`, `/dev/shm`, `/run`, `/tmp` and `/var/tmp` ([read-only-tmpfs][opt-rotmpfs],
  [podman-systemd.unit][psu]). So `Tmpfs=` below lists only app-specific paths; `/tmp` and
  `/run` never need their own line. `/var/run` is a symlink to `/run` in every image surveyed
  except fluent-bit and victoria-logs (layer listings).
- Volumes, including the anonymous volumes Podman creates for an image's `VOLUME` paths,
  stay writable under `ReadOnly` ([read-only][opt-ro]).
- Podman's default capability set is already smaller than Docker's: `CHOWN DAC_OVERRIDE
  FOWNER FSETID KILL NET_BIND_SERVICE SETFCAP SETGID SETPCAP SETUID SYS_CHROOT`, with no
  `NET_RAW`, `MKNOD` or `AUDIT_WRITE` ([containers.conf(5)][containers-conf]). `DropCapability=all`
  removes those eleven; nothing below needs one outside that set.
- `HealthCmd` as a plain string runs under `/bin/sh -c` (busybox `ash` on the Alpine images,
  which is fine); a JSON array runs directly ([health-cmd][opt-healthcmd]). The blocks use the
  plain string. Setting it resets interval/retries/timeouts to Podman's defaults even if the
  image has a `HEALTHCHECK`, hence the explicit `HealthInterval=30s`/`HealthRetries=3`. `HealthOnFailure=kill` kills the container on
  `unhealthy` and lets systemd's `Restart=on-failure` restart it ([health-on-failure][opt-hof],
  [podman-systemd.unit][psu]). `HealthStartPeriod` keeps a failing check in `starting`
  instead of `unhealthy` until it elapses ([health-start-period][opt-hsp]).
- **Frequency.** Podman runs each check from a systemd timer, every `HealthInterval` (30s),
  as a `podman healthcheck run` that execs the command in the container. A check fails on a
  non-zero exit or after `HealthTimeout` (default 30s). After 3 consecutive failures the
  container is `unhealthy` and killed. So a hung service restarts about 1.5 minutes after
  it hangs, or up to about 3 minutes if every probe times out. 12 core checks every 30s cost
  one short `podman exec` per node every few seconds.
- Quadlet copies these values into the generated `ExecStart=`, where systemd expands `$VAR`
  and `%` specifiers, so a literal `$` in a `HealthCmd` is written `$$` (the existing
  `vmalert.container.j2` does the same for `$$expr`). Only alertmanager's check has a `$`.
  Check each one with [Testing HealthCmd escaping](#testing-healthcmd-escaping).
- Six images already carry a `HEALTHCHECK` in their config (authelia, esphome, guacd, lldap,
  ntfy-alertmanager, homepage). If Podman honours them (unverified: `podman inspect
  --format '{{.Config.Healthcheck}}' <name>`), those containers already report health, with
  no action on failure. ntfy-alertmanager's probes `localhost:8080/health`, the port the
  repo listens on.
- `UserNS=auto` (rootful) needs a `containers` entry in `/etc/subuid` and `/etc/subgid`
  ([userns][opt-userns]); nothing in this repo creates one, so it's a per-node prerequisite:
  `echo containers:2147483647:2147483648 | tee -a /etc/subuid /etc/subgid`. Each new
  container gets a fresh range, and quadlet containers are recreated every start, so host
  files would appear with shifted owners. Append `idmap` to every `Volume=` (an idmapped mount
  keeps host ownership as seen from inside, [volume][opt-volume]) rather than `:U`, which
  re-chowns the host path, slowly, on every range change. "applied" in the UserNS column
  means: prerequisite done, `UserNS=auto`, and `idmap` on each `Volume=`. Do it as a second
  pass after caps/ReadOnly/health have settled.

### Verification loop (issue 01), per service

```bash
sudo su
svc=grafana   # the quadlet name
# Baseline, before editing
podman inspect --format '{{.EffectiveCaps}}' "$svc"
podman diff "$svc"                     # paths written into the container layer = Tmpfs/Volume candidates
# Apply the block from the template (deploy as usual), then check what quadlet generates
/usr/lib/systemd/system-generators/podman-system-generator --dryrun 2>/dev/null \
  | sed -n "/^---${svc}.service---/,/^---/p" | grep -E 'ExecStart|health|cap-|read-only|tmpfs|userns'
systemctl daemon-reload && systemctl restart "$svc"   # HealthCmd: see "Testing HealthCmd escaping"
journalctl -u "$svc" -n 80 --no-pager  # "Operation not permitted" → add back one capability;
                                       # "Read-only file system" → add a Tmpfs= or Volume= for that path
podman inspect --format '{{.EffectiveCaps}} ro={{.HostConfig.ReadonlyRootfs}}' "$svc"
podman healthcheck run "$svc"; echo "exit=$?"     # 0 = healthy
podman inspect --format '{{.State.Health.Status}}' "$svc"
# Repeat: start from DropCapability=all, add back one cap at a time until healthy;
# start ReadOnly, read the first write failure, add the path, repeat.
```

Exercise the app (log in, trigger the feature) before calling it done: some writes and
capability uses only happen on a code path, not at startup.

### Testing HealthCmd escaping

A `HealthCmd` passes through three parsers: quadlet writes it into `ExecStart=`, systemd
unquotes it and expands `$`/`%`, and Podman stores it (a plain string as `CMD-SHELL`, run by
`/bin/sh -c`). Check each stage, so a broken check is caught before `HealthOnFailure=kill`
starts restarting the service:

```bash
sudo su
svc=alertmanager   # the one with a `$`; repeat for each service with a health check
# 1. Quadlet output, before anything is reloaded: the raw --health-cmd argument
/usr/lib/systemd/system-generators/podman-system-generator --dryrun 2>/dev/null \
  | sed -n "/^---${svc}.service---/,/^---/p" | grep '^ExecStart=' | grep -o -- '--health-cmd.*'
# 2. The argv systemd will exec, after its unquoting and $/% expansion
systemctl daemon-reload
systemctl show -p ExecStart --value "$svc" | grep -o -- '--health-cmd.*'
# 3. What Podman stored: ["CMD-SHELL","<the command>"], quotes and pipes intact
systemctl restart "$svc"
podman inspect --format '{{json .Config.Healthcheck.Test}}' "$svc"
# 4. Run it once by hand, then check the timer picked it up
podman healthcheck run "$svc"; echo "exit=$?"
systemctl list-timers --all | grep "$(podman inspect --format '{{.Id}}' "$svc")"
```

Expected for alertmanager: stage 1 shows `$${AM_ADMIN_PASSWORD}`, and stages 2 and 3 show
`${AM_ADMIN_PASSWORD}` literally, for the container's shell to expand. If stage 3 shows
`http://admin:@127.0.0.1`, systemd expanded the variable (to nothing); double the `$` again.
For ntfy, check the `| grep -q '"healthy":true'` survives with its quotes.

## Summary

Cells: *applied* (block below adds it), *blocked by X*, *n/a*. "Tmpfs" lists only paths
beyond the automatic `/tmp`, `/run`, `/var/tmp`, `/dev/shm`. Client = what a `HealthCmd` can
call, from the layer listing.

| Node | Container | Image:tag (resolved) | Drop/AddCapability | ReadOnly | Tmpfs | UserNS=auto | HealthCmd | Client in image |
|---|---|---|---|---|---|---|---|---|
| secsvcs | postgres | `postgres:14-alpine` (14.24, alpine 3.24) | applied: all; add CHOWN DAC_OVERRIDE SETUID SETGID (entrypoint chown + gosu) | applied | none (socket dir is in `/run`) | applied (volume owned 70:70) | `pg_isready` | pg_isready, busybox |
| secsvcs | lldap | `lldap:stable` (v0.6.3-alpine) | applied: all; add CHOWN SETUID SETGID (entrypoint chown + gosu) | blocked by entrypoint chowning `/app` while `UID=0` | n/a | applied | `lldap healthcheck` (image's own) | lldap binary, curl, busybox |
| secsvcs | authelia | `authelia:4.39` (4.39.28) | applied: all, none added once `Exec=authelia` skips the su-exec branch | applied, needs `server.disable_healthcheck: true` (startup writes `/app/.healthcheck.env`) | none | applied | wget `/api/health` (https), as the image's `healthcheck.sh` | GNU wget, busybox |
| secsvcs | traefik | `traefik:v3.7` (v3.7.14) | applied: all; add NET_BIND_SERVICE (80/443/465) | applied | none (local plugins only) | applied | `traefik healthcheck`, needs `ping` in static config | traefik binary, busybox |
| secsvcs | victoriametrics | `victoria-metrics:latest` (v1.153.0) | applied: all, none added | applied | none | applied | wget `/health` | busybox |
| secsvcs | victorialogs | `victoria-logs:latest` (v1.53.0) | applied: all, none added | applied | none | applied | n/a: no shell or client (distroless); covered by `up{job="victorialogs"}` + Gatus | none |
| secsvcs | gatus | `gatus:latest` (rev c9aa339) | applied: all, none added | applied | none | applied | n/a: scratch image, binary has no health subcommand; covered by `up{job="gatus"}` | none |
| secsvcs | vmalert | `vmalert:latest` (v1.153.0) | applied: all, none added | applied | none | applied | wget `/health` | busybox |
| secsvcs | alertmanager | `prom/alertmanager:latest` (built 2026-09-17) | applied: all, none added (runs as `nobody`) | applied | none (`/alertmanager` is an image volume) | applied | wget `/-/healthy` with basic auth | busybox, amtool |
| secsvcs | ntfy-alertmanager | `xenrox/ntfy-alertmanager:latest` (built 2026-08-25) | applied: all, none added | applied | none | applied | curl `/health` on 8080 (outside auth; the image's own check) | curl, busybox |
| secsvcs | ntfy | `binwiederhier/ntfy:latest` (built 2026-10-07) | applied: all; add NET_BIND_SERVICE (SMTP `:25`) | applied | none | applied | wget `/v1/health` | busybox |
| secsvcs | grafana | `grafana-oss:latest` (13.0.2) | applied: all, none added (runs as 472) | applied | none | applied (volume 472:0) | curl `/api/health` | curl, busybox |
| secsvcs | olive_tin | `olivetin:latest-3k` (3000.20.0) | applied: all, none added (runs as 1000) | applied | none | applied | none: not core (candidate: curl `/readyz`) | curl, bash |
| all 4 | fluentbit | `fluent-bit:3.2` (3.2.10) | applied: all, none added | applied | none | applied (journal read via idmap, unverified) | n/a: distroless, no shell; covered by `up{job="fluentbit"}` + `NoOutputBytesProcessed` | none |
| homesvcs, websvcs, vpnsvcs | vmagent | `vmagent:latest` (v1.153.0) | applied: all, none added | applied | none | applied | wget `/health` | busybox |
| homesvcs | traefik | as secsvcs | as secsvcs | applied | none (local plugins only) | applied | as secsvcs | as secsvcs |
| homesvcs | mosquitto | `eclipse-mosquitto:latest` (2.1.2) | applied: all; add CHOWN SETUID SETGID (entrypoint chown, broker drops to 1883) | applied | none | applied | `nc -z` on 8883 (the only listener requires a client cert) | mosquitto_sub, busybox |
| homesvcs | zigbee2mqtt | `koenkk/zigbee2mqtt:latest` (2.14.2) | applied: all, none added (adapter is `mdns://`, no serial device) | applied | none | applied | none: not core (candidate: wget `/` on 8080) | busybox, node |
| homesvcs | esphome | `esphome:stable` (2026.9.1) | applied: all, none added (unverified on compile) | blocked by PlatformIO/ESP-IDF writing under `/root` at compile time | n/a | applied | none: not core (candidate: the image's own curl `/version`) | curl |
| homesvcs | home_assistant | `home-assistant:2026.3.1` | applied: all; add CHOWN DAC_OVERRIDE FOWNER SETUID SETGID (s6-overlay init, unverified) | blocked by runtime `uv pip install` into system site-packages | n/a | blocked by s6-overlay + 4 volumes, untested; revisit last | none: not core (candidate: curl `/`) | curl, busybox |
| websvcs | traefik | as secsvcs | NET_BIND_SERVICE (80/443) | applied | none (local plugins only) | applied | as secsvcs | as secsvcs |
| websvcs | nginx | `nginx:stable` (1.30.5, trixie) | applied: all; add CHOWN SETUID SETGID (master chowns temp dirs, workers run as `nginx`) | applied | `/var/cache/nginx` | applied | none: not core (candidate: curl any HTTP status on 8100) | curl |
| websvcs | homepage | `gethomepage/homepage:latest` (v2.5.0) | applied: all; add CHOWN SETUID SETGID (entrypoint chown + su-exec to `PUID`) | applied | `/app/.next/cache` (unverified) | applied | none: not core (candidate: the image's own wget `/api/healthcheck`) | busybox, node |
| websvcs | isso | `isso:release` (0.14.0) | applied: all, none added | applied | none (`--worker-tmp-dir /dev/shm`) | applied | none: not core (candidate: wget `/config` on 8080) | busybox, python |
| websvcs | guacamole | `guacamole:1.6.0` | applied: all, none added (runs as `guacamole`) | applied (entrypoint builds `GUACAMOLE_HOME` and `CATALINA_BASE` in `/tmp`) | none | applied | none: not core (candidate: curl `/`) | curl, wget |
| websvcs | guacd | `guacd:1.6.0` | applied: all, none added (runs as `guacd`) | applied | none | applied | none: not core (candidate: the image's own `nc -z` 4822) | netcat-openbsd, busybox |
| websvcs | archivebox | `archivebox:stable` (0.7.4) | applied after dropping `User=archivebox`: all; add CHOWN DAC_OVERRIDE FOWNER SETUID SETGID | blocked by entrypoint `usermod`/`groupmod` and `mkdir /browsers/...` | n/a | blocked by entrypoint usermod/chown; revisit after caps | none: not core (candidate: curl `/health/`) | curl, wget |
| websvcs | novnc | `localhost/novnc` (babraham123/docker-novnc) | applied: all, none added (unverified) | blocked by entrypoint `rm /app/conf.d/*.conf` and supervisord pid/log in `/` | n/a | applied (no volumes) | none: not core (candidate: bash `/dev/tcp` on 5900) | bash |
| websvcs | finance_exporter | `localhost/finance_exporter` (python:3-slim-bookworm) | applied: all, none added | applied | `/root/.cache` (yfinance cache, unverified) | applied | none: not core (candidate: python urllib `/metrics` on 8002) | python |
| websvcs | go2rtc | `alexxit/go2rtc:latest` (1.9.14) | applied: all, none added (`/dev/dri` is root-owned on the host) | applied | none | blocked by `/dev/dri` (render group not mapped into the namespace) | none: not core (candidate: curl `/api`) | curl, busybox |
| websvcs | piper | `localhost/piper` (wyoming-addons) | applied: all, none added | applied | `/root/.cache` (unverified) | applied | none: not core (candidate: python socket on 10200) | curl, python |
| websvcs | whisper | `localhost/whisper` (wyoming-addons) | applied: all, none added | applied | `/root/.cache` (unverified) | blocked by `--gpus=all` device nodes | none: not core (candidate: python socket on 10300) | python |
| websvcs | openwakeword | `localhost/openwakeword` (wyoming-addons) | applied: all, none added | applied | `/root/.cache` (unverified) | applied | none: not core (candidate: venv python socket on 10400) | python (venv) |
| vpnsvcs | geoip_generator | `localhost/geoip_generator` | not surveyed (added after the survey) | not surveyed | not surveyed | not surveyed | none: a timer-run job, not a service | |

Easy (caps all dropped, read-only; health check if core): victoriametrics, vmagent,
vmalert, alertmanager, ntfy-alertmanager, ntfy, grafana, victorialogs, gatus, fluentbit,
olive_tin, zigbee2mqtt, isso, guacamole, guacd, go2rtc, finance_exporter, the wyoming trio.
Need care: traefik (loopback `ping` entrypoint), postgres and nginx and mosquitto and homepage
(entrypoints need CHOWN/SETUID/SETGID), authelia (config switch), lldap (read-only blocked
while `UID=0`). Hard: home_assistant, esphome, archivebox, novnc.

## Per-container blocks

Paste into the `[Container]` section next to the existing `NoNewPrivileges=true`. Lines
already in the quadlet (`AddCapability=CAP_NET_BIND_SERVICE` on Traefik) are repeated so the
block is complete. The `UserNS=auto` pass is listed separately per container.

### secsvcs

#### postgres (`docker.io/library/postgres:14-alpine`)

Image runs as root; `docker-entrypoint.sh` creates `$PGDATA` and `/var/run/postgresql`,
`find … -exec chown postgres` on both, then `exec gosu postgres` ([entrypoint][pg-entry]).
Needs CHOWN, SETUID/SETGID (gosu), DAC_OVERRIDE (root traversing the 0700 `$PGDATA` owned
by 70). The `chmod 00700 "$PGDATA" || :` would need FOWNER but its failure is ignored, so
it's left out. `/var/run` → `/run` (layer listing), covered by `ReadOnlyTmpfs`; data is
the named volume.

```ini
DropCapability=all
AddCapability=CAP_CHOWN CAP_DAC_OVERRIDE CAP_SETUID CAP_SETGID
ReadOnly=true
HealthCmd=pg_isready -q -U postgres
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
HealthStartPeriod=60s
```

UserNS pass: `UserNS=auto`; `Volume=postgresdb.volume:/var/lib/postgresql/data:idmap`, and
`idmap` added to the init script and certificate mounts. Last on secsvcs.

#### lldap (`docker.io/lldap/lldap:stable`)

`docker-entrypoint.sh` runs `find /app \! -user "$UID" -exec chown` and the same on
`/data`, then `exec gosu "$UID:$GID" /app/lldap` under `set -euo pipefail`
([entrypoint][lldap-entry]). With `Environment=UID=0 GID=0` every `/app` file (shipped
owned by `lldap`, image history) is chowned on each start, which fails on a read-only root
and aborts the script. Image has its own `HEALTHCHECK /app/lldap healthcheck --config-file
/data/lldap_config.toml` (config blob).

```ini
DropCapability=all
AddCapability=CAP_CHOWN CAP_SETUID CAP_SETGID
HealthCmd=/app/lldap healthcheck --config-file /data/lldap_config.toml
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
HealthStartPeriod=30s
```

To unblock `ReadOnly`: switch to the image's default `UID=1000 GID=1000` and
`chown -R 1000:1000 /etc/opt/lldap` on the host once; then `find /app` has nothing to chown
and `ReadOnly=true` should hold (unverified). UserNS pass: `UserNS=auto`, `:idmap` on
`/etc/opt/lldap:/data`.

#### authelia (`docker.io/authelia/authelia:4.39`)

`entrypoint.sh`: if `$1` is set and isn't `--config`, it `exec`s it; as root with
`PUID=0` it otherwise runs `chown -R` on `/config` and `su-exec` ([entrypoint][authelia-entry]),
and su-exec's `setgroups` needs SETGID. `Exec=authelia` takes the first branch, so
nothing needs a capability (port 9091). At startup Authelia writes `/app/.healthcheck.env`
and returns the error if it can't ([startup.go][authelia-startup]); on a read-only root
that aborts startup, so set `server.disable_healthcheck: true` in
`src/services/authelia/configuration.yml.j2` and probe directly with the same wget call the shipped
`healthcheck.sh` makes ([healthcheck.sh][authelia-hc]); that `wget` is GNU Wget
([baseimage Dockerfile][authelia-base]). Scheme is https: the repo config sets `server.tls`.

```ini
Exec=authelia
DropCapability=all
ReadOnly=true
HealthCmd=wget --quiet --no-check-certificate --tries=1 --spider https://127.0.0.1:9091/api/health
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
HealthStartPeriod=60s
```

UserNS pass: `UserNS=auto`, `:idmap` on `/config` and `/certificates`.

#### traefik (`docker.io/library/traefik:v3.7`), same for homesvcs and websvcs

Runs as root, binds 80/443 (and 465 on secsvcs): keep `NET_BIND_SERVICE`. The entrypoint
only rewrites arguments ([entrypoint][traefik-entry]). Only remote plugins
(`experimental.plugins`) are downloaded to `./plugins-storage/`; the static config declares
only `experimental.localPlugins`, read from the read-only `/plugins-local` mount
([plugins.go][traefik-plugins]), so no tmpfs is needed.
`traefik healthcheck` reads the static config and fails with "please enable `ping`" unless
`ping` is set, then sends `HEAD` to the ping entrypoint ([healthcheck.go][traefik-hc],
[ping docs][traefik-ping]). Add a loopback-only entrypoint to
`src/services/traefik/static.yml.j2` so `/ping` isn't reachable from the bridge (`:8082` is
already the `metrics` entrypoint):

```yaml
entryPoints:
  ping:
    address: "127.0.0.1:8083/tcp"
ping:
  entryPoint: ping
```

```ini
DropCapability=all
AddCapability=CAP_NET_BIND_SERVICE
ReadOnly=true
HealthCmd=traefik healthcheck --configFile=/config/static/traefik.yml
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
HealthStartPeriod=60s
```

UserNS pass: `UserNS=auto`, `:idmap` on `/config`, `/certificates` (ACME writes
`acme.json` there) and `/plugins-local`. Last on every node.

#### victoriametrics, vmagent, vmalert (`docker.io/victoriametrics/*:latest`)

Alpine-based (busybox `wget`), root, ports above 1024, write only to their volume
(`/storage`, `/vmagentdata`; vmalert writes nothing). `/health` is answered before the
`-httpAuth.*` check ([httpserver.go][vm-http]), so no credentials are needed.

```ini
DropCapability=all
ReadOnly=true
HealthCmd=wget -q -O /dev/null http://127.0.0.1:8428/health
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
```

Port per service: victoriametrics 8428, vmagent 8429, vmalert 8880. UserNS pass:
`UserNS=auto`, `:idmap` on each volume.

#### victorialogs (`docker.io/victoriametrics/victoria-logs:latest`)

Distroless (bazel-built Debian 13 base, history), only `/victoria-logs-prod`, no shell or
client (layer listing). Options: (a) skip `HealthCmd`; (b) the binary as a probe: it has
no health subcommand; (c) a sidecar. Recommended: **skip**; it's already scraped
(`job: victorialogs`) and has a Gatus check.

```ini
DropCapability=all
ReadOnly=true
```

UserNS pass: `UserNS=auto`, `vldata.volume:/storage:idmap`.

#### gatus (`docker.io/twinproduction/gatus:latest`)

Scratch: seven files, `/gatus`, its sample config and CA bundle (layer listing). `main.go`
has no health subcommand ([main.go][gatus-main]). Storage is Postgres (repo config), so
nothing is written locally. Recommended: **skip** `HealthCmd`; scraped as `job: gatus`.

```ini
DropCapability=all
ReadOnly=true
```

UserNS pass: `UserNS=auto`, `:idmap` on both file mounts.

#### alertmanager (`docker.io/prom/alertmanager:latest`)

Runs as `nobody`; `/alertmanager` is an image `VOLUME` (history), so it stays writable.
Busybox `wget` present. With `basic_auth_users` set, exporter-toolkit authenticates every
path, `/-/healthy` included ([handler.go][et-handler]). Inject the existing
`alertmanager_admin_password` secret and pass it in the URL (busybox wget sends URL userinfo
as Basic auth). If the password ever contains URL-reserved characters, switch to `amtool
--http.config.file` with a `basic_auth.password_file` ([root.go][amtool-root]).

```ini
DropCapability=all
ReadOnly=true
Secret=alertmanager_admin_password,type=env,target=AM_ADMIN_PASSWORD
HealthCmd=wget -q -O /dev/null http://admin:$${AM_ADMIN_PASSWORD}@127.0.0.1:9093/-/healthy
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
```

UserNS pass: `UserNS=auto`, `:ro,idmap` on `/config`. The `ExecStartPre=chown nobody:nogroup`
keeps working with idmap; without idmap it would need the shifted uid.

#### ntfy-alertmanager (`docker.io/xenrox/ntfy-alertmanager:latest`)

Alpine + `curl` (history). `GET /health` is registered on the outer mux, outside the auth
middleware ([main.go][ntfy-am-main]). The image's own `HEALTHCHECK` is
`curl --fail http://localhost:8080/health` (config blob); the repo now listens on 8080 to
match. The explicit `HealthCmd` is still needed to add `HealthOnFailure=kill`.

```ini
DropCapability=all
ReadOnly=true
HealthCmd=curl -fsS -o /dev/null http://127.0.0.1:8080/health
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
```

UserNS pass: `UserNS=auto`, `:ro,idmap` on the config file.

#### ntfy (`docker.io/binwiederhier/ntfy:latest`)

Alpine (busybox wget), root, `ENTRYPOINT ["ntfy"]`. `server.yml` sets
`smtp-server-listen: ":25"`, so NET_BIND_SERVICE stays. Health from ntfy's docs
([install.md][ntfy-install]), port from `listen-http: ":2586"`. ntfy's JSON has no spaces,
so a fixed-string grep works with busybox's.

```ini
DropCapability=all
AddCapability=CAP_NET_BIND_SERVICE
ReadOnly=true
HealthCmd=wget -q --tries=1 -O - http://127.0.0.1:2586/v1/health | grep -q '"healthy":true'
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
```

UserNS pass: `UserNS=auto`, `:idmap` on `/var/cache/ntfy` and `ntfydb.volume`.

#### grafana (`docker.io/grafana/grafana-oss:latest`)

`USER 472`; `run.sh` only `mkdir`s the plugins dir under the data path and forces
`log.mode=console` ([run.sh][grafana-run]); data, plugins and dashboards live in
`grafanadata.volume`. `preinstall_sync` downloads plugins on start, hence the start period.

```ini
DropCapability=all
ReadOnly=true
HealthCmd=curl -fsS -o /dev/null http://127.0.0.1:3000/api/health
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
HealthStartPeriod=2m
```

UserNS pass: `UserNS=auto`, `:idmap` on every mount (volume owned 472:0).

#### olive_tin (`docker.io/jamesread/olivetin:latest-3k`)

Fedora-minimal, `USER olivetin` (1000), `/config` is an image volume and a bind here
([Dockerfile][olivetin-df]). `/readyz` returns 200 unauthenticated ([frontend.go][olivetin-fe]).
SSH uses the read-only `~/.ssh` and host `/etc/ssh`; `ReadOnly` is fine unless ssh needs to
write `known_hosts` (unverified: run one action).

```ini
DropCapability=all
ReadOnly=true
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`curl -fsS -o /dev/null http://127.0.0.1:1337/readyz`.

UserNS pass: `UserNS=auto`, `:idmap` on all four mounts.

#### fluentbit (`docker.io/fluent/fluent-bit:3.2`), all four nodes

Distroless: `/fluent-bit/bin/fluent-bit`, certs and dpkg metadata only, `User 0` (config
blob, layer listing). Reads the host journal (root-owned), writes its cursor DB to
`/data/fb_journald.db` (`fbdata.volume`). `/api/v1/health` would also need
`health_check: on` ([monitoring docs][fb-monitoring]) and a client. Recommended: **skip**
`HealthCmd`; covered by `up{job="fluentbit"}` and the existing `NoOutputBytesProcessed`
rule.

```ini
DropCapability=all
ReadOnly=true
```

UserNS pass: `UserNS=auto`, `:idmap` on the journal and machine-id mounts (reading
`root:systemd-journal` files through idmap is unverified).

### homesvcs

#### traefik, vmagent, fluentbit

As on secsvcs (vmagent port 8429).

#### mosquitto (`docker.io/eclipse-mosquitto:latest`)

Entrypoint chowns `/mosquitto/data` to 1883 when run as root ([entrypoint][mosq-entry]),
then the broker drops to `mosquitto` (the repo already chowns the key to 1883 for this,
`src/nodes/homesvcs/commands.sh.j2`). Needs CHOWN, SETUID, SETGID. `/mosquitto/log` is an image
volume. The only listener is 8883 with `require_certificate true`, so `mosquitto_sub`
needs a client certificate the container doesn't have. Options: (a) TCP liveness with
busybox `nc -z` (`-z` support in this busybox unverified); (b) issue a `healthcheck` client
cert in `src/nodes/homesvcs/commands.sh.j2` like zigbee2mqtt's, then
`mosquitto_sub -h mqtt.{{ site.url }} -p 8883 --cafile … --cert … --key …
-t '$$SYS/broker/uptime' -C 1 -W 5`. Recommended: (a) now, (b) if a hung-but-listening
broker is ever seen.

```ini
DropCapability=all
AddCapability=CAP_CHOWN CAP_SETUID CAP_SETGID
ReadOnly=true
HealthCmd=nc -z 127.0.0.1 8883
HealthInterval=30s
HealthRetries=3
HealthOnFailure=kill
```

UserNS pass: `UserNS=auto`, `:idmap` on all mounts.

#### zigbee2mqtt (`ghcr.io/koenkk/zigbee2mqtt:latest`)

Entrypoint only echoes the data dir ([entrypoint][z2m-entry]); root, no device: the
coordinator is `port: mdns://slzb-06` (repo config), so the "serial device" concern in
issue 01 doesn't apply. Writes `/app/data` (volume and config-file binds). Frontend on 8080,
no `auth_token`.

```ini
DropCapability=all
ReadOnly=true
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`wget -q -O /dev/null http://127.0.0.1:8080/`.

UserNS pass: `UserNS=auto`, `:idmap` on all mounts.

#### esphome (`docker.io/esphome/esphome:stable`)

Root; the entrypoint puts PlatformIO platforms/packages and the ESP-IDF/nRF SDKs under
`/config/.esphome`, but says it can't move PlatformIO's `core_dir` (`~/.platformio`, which
holds `appstate.json`), and the dashboard is now `esphome-device-builder`
([entrypoint][esphome-entry]). Compiles write under
`/root`, so `ReadOnly` is blocked unless `/root` gets a volume (low value). No capability
need is documented; `ESPHOME_DASHBOARD_USE_PING` uses ICMP, and `NET_RAW` isn't in Podman's
default set today, so dropping all doesn't change ping. Health: keep the image's own probe
([Dockerfile][esphome-df]).

```ini
DropCapability=all
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`curl --fail -A HealthCheck -o /dev/null http://127.0.0.1:6052/version`.

Unverified: a full compile + OTA with all caps dropped. UserNS pass: `UserNS=auto`,
`:idmap` on `/config`.

#### home_assistant (`docker.io/homeassistant/home-assistant:2026.3.1`)

`ENTRYPOINT ["/init"]` (s6-overlay 3.1.6.2), service `run` execs `python3 -m
homeassistant` as root ([run][ha-run]). In a container, HA installs integration
requirements without `--target` ([requirements.py][ha-req]), i.e. into the image's
site-packages (`UV_SYSTEM_PYTHON=true` in the config), so `ReadOnly` would break any
integration or HACS component that pulls a package at runtime: **blocked**. Capabilities:
s6-overlay's init needs are undocumented; start from the set below and remove one at a time.

```ini
DropCapability=all
AddCapability=CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_SETUID CAP_SETGID
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`curl -fsS -o /dev/null http://127.0.0.1:8123/`.

`Environment=PACKAGES=iputils` looks like a linuxserver.io convention; the official image's
config `Env` and `run` script don't reference it (other s6 scripts unchecked). UserNS: deferred to last; four volumes
and s6 untested.

### websvcs

#### traefik, vmagent, fluentbit

As on secsvcs; websvcs Traefik binds 80/443 only.

#### nginx (`docker.io/library/nginx:stable`)

Master runs as root and workers as `nginx`; the image docs say read-only needs
`/var/cache/nginx` and `/var/run` writable ([nginx docs][nginx-docs]); `/var/run` → `/run` is
covered. Entrypoint scripts no-op on a read-only `/etc/nginx` (`10-listen-on-ipv6` exits
on a failed `touch`, `20-envsubst` needs `/etc/nginx/templates`) ([entrypoint][nginx-entry],
[10-listen][nginx-10]). Caps: CHOWN for the temp dirs, SETUID/SETGID for the workers.
Health: any HTTP response proves the server is up independent of which content is deployed,
so `curl` without `-f`.

```ini
DropCapability=all
AddCapability=CAP_CHOWN CAP_SETUID CAP_SETGID
ReadOnly=true
Tmpfs=/var/cache/nginx
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`curl -s -o /dev/null http://127.0.0.1:8100/`.

UserNS pass: `UserNS=auto`, `:ro,idmap` on both mounts.

#### homepage (`ghcr.io/gethomepage/homepage:latest`)

`USER root`; entrypoint chowns `/app/config` (and `/app/config/logs`) to `PUID:PGID` when
they differ, then `su-exec 1000:1000` ([entrypoint][homepage-entry]). `/app/.next` ships
owned 1000 so that chown is skipped. Next.js writes its image cache to `/app/.next/cache`
(unverified path, hence the tmpfs). The image `HEALTHCHECK` probes `/api/healthcheck`
([Dockerfile][homepage-df]); `127.0.0.1:3000` is always an allowed host ([docs][homepage-docs]).

```ini
DropCapability=all
AddCapability=CAP_CHOWN CAP_SETUID CAP_SETGID
ReadOnly=true
Tmpfs=/app/.next/cache
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`wget -q --tries=1 --spider -Y off http://127.0.0.1:3000/api/healthcheck` (the image's own).

UserNS pass: `UserNS=auto`, `:idmap` on both mounts.

#### isso (`ghcr.io/isso-comments/isso:release`)

Root; `ENTRYPOINT` is gunicorn bound to `0.0.0.0:8080` with `--worker-tmp-dir /dev/shm`
([Dockerfile][isso-df]); `/db` and `/config` are image volumes, the DB is `issodb.volume`.
`GET /config` is a cheap unauthenticated route ([comments.py][isso-views]). The repo uses
port 8080 everywhere
(quadlet comment, `[server] listen`, Traefik route), matching the gunicorn bind.

```ini
DropCapability=all
ReadOnly=true
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`wget -q -O /dev/null http://127.0.0.1:8080/config`.

UserNS pass: `UserNS=auto`, `:idmap` on both mounts.

#### guacamole (`docker.io/guacamole/guacamole:1.6.0`)

`USER guacamole` (1001), Tomcat 9. The 1.6.0 entrypoint builds a fresh `GUACAMOLE_HOME`
(links into the read-only `/etc/guacamole`) and a fresh `CATALINA_BASE` (`logs temp webapps
work`, WAR symlink) under `/tmp` on every start ([100-generate-guacamole-home][guac-100],
[500-generate-tomcat-catalina-base][guac-500], [999-start-tomcat][guac-999]), so read-only
needs nothing beyond the automatic `/tmp`. The unpacked WAR lives in that tmpfs (RAM).

```ini
DropCapability=all
ReadOnly=true
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`curl -fsS -o /dev/null http://127.0.0.1:8080/`.

UserNS pass: `UserNS=auto`, `:ro,idmap` on both mounts.

#### guacd (`docker.io/guacamole/guacd:1.6.0`)

`USER guacd` (1000), alpine with `netcat-openbsd`, `HEALTHCHECK nc -z 127.0.0.1 4822` every
5 m ([Dockerfile][guacd-df]); entrypoint just execs `guacd -f -b 0.0.0.0` ([entrypoint][guacd-entry]).
Not a hard case: nothing in the sources writes outside `/tmp`.

```ini
DropCapability=all
ReadOnly=true
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`nc -z 127.0.0.1 4822` (the image's own).

UserNS pass: `UserNS=auto` (no volumes).

#### archivebox (`docker.io/archivebox/archivebox:stable`)

`bin/docker_entrypoint.sh` (stable branch, [entrypoint][ab-entry]) expects root: `usermod`,
`groupmod` (writes `/etc/passwd`, `/etc/group`), `chown` of `/data` and `/browsers`, `mkdir
/browsers/permissions_test_safe_to_delete`, then `gosu`. The quadlet sets
`User=archivebox`, under which `gosu` can't `setgroups`; unverified whether the container
starts at all today (`systemctl status archivebox` on websvcs). Recommended: remove
`User=archivebox` (the entrypoint drops to 911 itself) and grant what it uses. `ReadOnly`
blocked by the `/etc` and `/browsers` writes. Health: `/health/` route ([urls.py][ab-urls]).

```ini
DropCapability=all
AddCapability=CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER CAP_SETUID CAP_SETGID
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`curl -fsS -o /dev/null http://127.0.0.1:8000/health/`.

UserNS: deferred; retest after the entrypoint runs cleanly.

#### novnc (`localhost/novnc:latest`, built from babraham123/docker-novnc)

Debian trixie, root, `supervisord` with Xvfb/x11vnc/fluxbox ([Dockerfile][novnc-df]).
`entrypoint.sh` deletes `/app/conf.d/*.conf` for disabled programs ([entrypoint][novnc-entry]),
and `supervisord.conf` sets no `pidfile`/`logfile` ([supervisord.conf][novnc-sup]), so
supervisord writes them in its cwd `/`: `ReadOnly` blocked. Only run intermittently (quadlet
comment), so lowest priority.

```ini
DropCapability=all
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`bash -c '</dev/tcp/127.0.0.1/5900'`.

UserNS pass: `UserNS=auto` (no volumes).

#### finance_exporter (`localhost/finance_exporter:latest`)

`python:3-slim-bookworm`, root, `CMD sh -c "python3 finance-exporter.py -f ${CONFIG}"`
([Dockerfile][fe-df]); `prometheus_client.start_http_server` on `port: 8002` (repo config).
No curl/wget in slim; python is. yfinance keeps a cache under the user cache dir
(unverified), hence the tmpfs.

```ini
DropCapability=all
ReadOnly=true
Tmpfs=/root/.cache
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8002/metrics', timeout=5)"`.

UserNS pass: `UserNS=auto`, `:ro,idmap` on the config file.

#### go2rtc (`docker.io/alexxit/go2rtc:latest`)

`python:3.13-alpine` + `curl`, root, `tini` ([Dockerfile][go2rtc-df]). The API skips basic
auth for loopback requests unless `local_auth` is set ([api.go][go2rtc-api]). `/dev/dri`
render nodes are owned by host root, so container root opens them without
DAC_OVERRIDE; that same ownership is what blocks `UserNS=auto` (unmapped owner → no
access).

```ini
DropCapability=all
ReadOnly=true
```

No `HealthCmd`: not a core service. Candidate if one is wanted later:
`curl -fsS -o /dev/null http://127.0.0.1:1984/api`.

Unverified: hardware transcoding with all caps dropped (`vainfo`-style open of
`/dev/dri/renderD128`).

#### piper, whisper, openwakeword (`localhost/*:latest`, built from rhasspy/wyoming-addons)

`debian:bookworm-slim`, root, `bash /run.sh` → python server on 10200/10300/10400; models
download to `/data` ([piper][wy-piper], [whisper][wy-whisper], [openwakeword][wy-oww]).
Wyoming is raw TCP, so a probe would be a socket connect. openwakeword's python is the venv at
`/usr/src/.venv`; Debian's system `python3` is also installed there. HuggingFace/torch may
cache under `/root/.cache` (unverified). Whisper uses `PodmanArgs=--gpus=all`, which blocks
`UserNS=auto` for the same reason as go2rtc.

```ini
DropCapability=all
ReadOnly=true
Tmpfs=/root/.cache
```

No `HealthCmd`: not a core service, and not in use. Candidate if one is wanted later:
`python3 -c "import socket; socket.create_connection(('127.0.0.1', 10200), 5)"` with
`HealthStartPeriod=5m` for the first-start model download. Port per service: piper 10200,
whisper 10300, openwakeword 10400.

## Apply order

One service per commit, so a regression bisects to one quadlet. Caps + ReadOnly + health
first; the `UserNS=auto` pass after, per node, once `/etc/subuid`/`/etc/subgid` exist.

- secsvcs: vmalert, victoriametrics, victorialogs, gatus, alertmanager, ntfy-alertmanager,
  ntfy, fluentbit, grafana, olive_tin, lldap, authelia, traefik, postgres
- homesvcs: vmagent, fluentbit, zigbee2mqtt, mosquitto, esphome, home_assistant, traefik
- websvcs: vmagent, fluentbit, finance_exporter, guacd, guacamole, isso, go2rtc, nginx,
  homepage, novnc, archivebox, traefik
- vpnsvcs: vmagent, fluentbit

## Alerting on health (issue 02)

Chosen: systemd's restart counter, no new exporter. Every quadlet is a systemd service. When a
check fails `HealthRetries` times, `HealthOnFailure=kill` kills the container, the unit's main
process (`podman`) exits non-zero, and `Restart=on-failure` starts it again. systemd counts
each automatic restart in `NRestarts` (`systemctl show -p NRestarts grafana`).

`node_exporter` already runs the systemd collector on every VM, filtered to the `Homelab:`
units (`src/base/node_exporter/node_runner.sh`). `--collector.systemd.enable-restarts-metrics`
exports `NRestarts` as `node_systemd_service_restart_total{name="grafana.service"}`
([systemd_linux.go][ne-systemd]). Both pieces are in the repo:

- the flag in `node_runner.sh`;
- `ServiceRestartLoop` in `src/services/vmalert/configs/homelab.yml`:
  `increase(node_systemd_service_restart_total[1h]) > 3`, next to the existing
  `SystemdUnitFailed`, which takes over once `StartLimitBurst` stops the restarts.

It also catches crash loops in services with no health check. What it can't tell you:

- **Why the service restarted.** A failed health check and a crash look the same; the
  journal says which (Podman logs `health_status=unhealthy`).
- **Unhealthy but still running.** Only the image's own `HEALTHCHECK`s (no kill) end up there.
  If that ever matters, [prometheus-podman-exporter][ppe-readme] exports
  `podman_container_health` per container id, joined to names through `podman_container_info`
  ([container.go][ppe-container]).

## Open items (unverified, test on node)

- Whether Podman runs the six image `HEALTHCHECK`s
  (`podman inspect --format '{{.Config.Healthcheck}}' <name>`).
- Each `HealthCmd` survives quadlet and systemd
  ([Testing HealthCmd escaping](#testing-healthcmd-escaping)); alertmanager's `$$` first.
- Busybox `nc -z` in the mosquitto image.
- Every capability set: especially postgres (first init on an empty volume too),
  home_assistant (s6-overlay), esphome (compile + OTA), archivebox, novnc, go2rtc
  (hardware transcoding).
- Read-only paths: homepage `/app/.next/cache`, finance_exporter and wyoming
  `/root/.cache`, olive_tin `known_hosts`, guacd recordings/drive if ever enabled.
- geoip_generator: not surveyed.
- lldap read-only after switching to `UID=1000`.
- archivebox: whether it starts at all with `User=archivebox`.
- `UserNS=auto`: `/etc/subuid`/`/etc/subgid` prerequisite; `idmap` on file and named-volume
  mounts; fluentbit reading the journal through idmap.

## Sources

Image configs and layer listings: registry HTTP API (`registry-1.docker.io`, `ghcr.io`),
manifest list → linux/amd64 manifest → config blob and layers, fetched 2026-10-10. Local
builds (novnc, finance_exporter, wyoming) from their repos' default branch, as
`install_svcs.sh` builds them.

Podman:
- [podman-systemd.unit(5) v5.8.2][psu]
- Options at v5.8.2: [health-cmd][opt-healthcmd], [health-on-failure][opt-hof],
  [health-start-period][opt-hsp], [read-only][opt-ro], [read-only-tmpfs][opt-rotmpfs],
  [userns][opt-userns], [volume][opt-volume]
- [containers.conf(5)][containers-conf]

Images:
- Traefik: [entrypoint][traefik-entry], [plugins.go v3.7.14][traefik-plugins],
  [healthcheck.go v3.7.14][traefik-hc], [ping docs][traefik-ping]
- Postgres: [docker-entrypoint.sh][pg-entry]
- lldap: [docker-entrypoint.sh][lldap-entry]
- Authelia v4.39.28: [entrypoint.sh][authelia-entry], [healthcheck.sh][authelia-hc],
  [startup.go][authelia-startup], [baseimage Dockerfile][authelia-base]
- VictoriaMetrics v1.153.0: [httpserver.go][vm-http]
- Gatus: [main.go][gatus-main]
- Alertmanager: [exporter-toolkit handler.go][et-handler], [amtool cli/root.go][amtool-root]
- ntfy-alertmanager: [main.go][ntfy-am-main]; ntfy: [install.md][ntfy-install]
- Grafana v13.0.2: [run.sh][grafana-run]
- OliveTin 3000.20.0: [Dockerfile.multiarches][olivetin-df], [frontend.go][olivetin-fe]
- Fluent Bit: [monitoring docs][fb-monitoring]
- Mosquitto 2.1.2: [docker-entrypoint.sh][mosq-entry]
- Zigbee2MQTT 2.14.2: [docker-entrypoint.sh][z2m-entry]
- ESPHome 2026.9.1: [docker_entrypoint.sh][esphome-entry], [Dockerfile][esphome-df]
- Home Assistant 2026.3.1: [s6 run][ha-run], [requirements.py][ha-req]
- nginx: [image docs][nginx-docs], [docker-entrypoint.sh][nginx-entry],
  [10-listen-on-ipv6-by-default.sh][nginx-10]
- Homepage v2.5.0: [docker-entrypoint.sh][homepage-entry], [Dockerfile][homepage-df],
  [installation docs][homepage-docs]
- Isso: [Dockerfile][isso-df], [views/comments.py][isso-views]
- Guacamole 1.6.0: [100-generate-guacamole-home.sh][guac-100],
  [500-generate-tomcat-catalina-base.sh][guac-500], [999-start-tomcat.sh][guac-999];
  guacd: [Dockerfile][guacd-df], [entrypoint.sh][guacd-entry]
- ArchiveBox stable (d1136d7): [docker_entrypoint.sh][ab-entry], [core/urls.py][ab-urls]
- docker-novnc: [Dockerfile][novnc-df], [entrypoint.sh][novnc-entry],
  [supervisord.conf][novnc-sup]
- finance-exporter: [Dockerfile][fe-df]
- go2rtc v1.9.14: [Dockerfile][go2rtc-df], [api.go][go2rtc-api]
- wyoming-addons: [piper][wy-piper], [whisper][wy-whisper], [openwakeword][wy-oww]

Observability:
- [prometheus-podman-exporter v2.0.0 README][ppe-readme], [collector/container.go][ppe-container]
- [node_exporter systemd collector][ne-systemd]

[psu]: https://github.com/containers/podman/blob/v5.8.2/docs/source/markdown/podman-systemd.unit.5.md
[opt-healthcmd]: https://github.com/containers/podman/blob/v5.8.2/docs/source/markdown/options/health-cmd.md
[opt-hof]: https://github.com/containers/podman/blob/v5.8.2/docs/source/markdown/options/health-on-failure.md
[opt-hsp]: https://github.com/containers/podman/blob/v5.8.2/docs/source/markdown/options/health-start-period.md
[opt-ro]: https://github.com/containers/podman/blob/v5.8.2/docs/source/markdown/options/read-only.md
[opt-rotmpfs]: https://github.com/containers/podman/blob/v5.8.2/docs/source/markdown/options/read-only-tmpfs.md
[opt-userns]: https://github.com/containers/podman/blob/v5.8.2/docs/source/markdown/options/userns.container.md
[opt-volume]: https://github.com/containers/podman/blob/v5.8.2/docs/source/markdown/options/volume.md
[containers-conf]: https://github.com/containers/container-libs/blob/main/common/docs/containers.conf.5.md
[traefik-entry]: https://github.com/traefik/traefik-library-image/blob/master/v3.7/alpine/entrypoint.sh
[traefik-plugins]: https://github.com/traefik/traefik/blob/v3.7.14/cmd/traefik/plugins.go
[traefik-hc]: https://github.com/traefik/traefik/blob/v3.7.14/cmd/healthcheck/healthcheck.go
[traefik-ping]: https://github.com/traefik/traefik/blob/v3.7/docs/content/reference/install-configuration/observability/healthcheck.md
[pg-entry]: https://github.com/docker-library/postgres/blob/master/14/alpine3.24/docker-entrypoint.sh
[lldap-entry]: https://github.com/lldap/lldap/blob/48a0a8d961f32bd8e3263b202053ce49a6c94781/docker-entrypoint.sh
[authelia-entry]: https://github.com/authelia/authelia/blob/v4.39.28/entrypoint.sh
[authelia-hc]: https://github.com/authelia/authelia/blob/v4.39.28/healthcheck.sh
[authelia-startup]: https://github.com/authelia/authelia/blob/v4.39.28/internal/middlewares/startup.go
[authelia-base]: https://github.com/authelia/baseimage/blob/master/Dockerfile
[vm-http]: https://github.com/VictoriaMetrics/VictoriaMetrics/blob/v1.153.0/lib/httpserver/httpserver.go
[gatus-main]: https://github.com/TwiN/gatus/blob/master/main.go
[et-handler]: https://github.com/prometheus/exporter-toolkit/blob/d4c9f37a5a9fc3d43930ff990bcfd6b8e037a6bc/web/handler.go
[amtool-root]: https://github.com/prometheus/alertmanager/blob/main/cli/root.go
[ntfy-am-main]: https://git.xenrox.net/~xenrox/ntfy-alertmanager/tree/master/item/main.go
[ntfy-install]: https://github.com/binwiederhier/ntfy/blob/main/docs/install.md
[grafana-run]: https://github.com/grafana/grafana/blob/v13.0.2/packaging/docker/run.sh
[olivetin-df]: https://github.com/OliveTin/OliveTin/blob/ed570ff888e2a4021d41cab1b18b44d353086c2c/Dockerfile.multiarches
[olivetin-fe]: https://github.com/OliveTin/OliveTin/blob/ed570ff888e2a4021d41cab1b18b44d353086c2c/service/internal/httpservers/frontend.go
[fb-monitoring]: https://github.com/fluent/fluent-bit-docs/blob/master/administration/monitoring.md
[mosq-entry]: https://github.com/eclipse-mosquitto/mosquitto/blob/v2.1.2/docker/2.1-alpine/docker-entrypoint.sh
[z2m-entry]: https://github.com/Koenkk/zigbee2mqtt/blob/2.14.2/docker/docker-entrypoint.sh
[esphome-entry]: https://github.com/esphome/esphome/blob/2026.9.1/docker/docker_entrypoint.sh
[esphome-df]: https://github.com/esphome/esphome/blob/2026.9.1/docker/Dockerfile
[ha-run]: https://github.com/home-assistant/core/blob/2026.3.1/rootfs/etc/services.d/home-assistant/run
[ha-req]: https://github.com/home-assistant/core/blob/2026.3.1/homeassistant/requirements.py
[nginx-docs]: https://github.com/docker-library/docs/blob/master/nginx/content.md
[nginx-entry]: https://github.com/nginxinc/docker-nginx/blob/master/stable/debian/docker-entrypoint.sh
[nginx-10]: https://github.com/nginxinc/docker-nginx/blob/master/stable/debian/10-listen-on-ipv6-by-default.sh
[homepage-entry]: https://github.com/gethomepage/homepage/blob/v2.5.0/docker-entrypoint.sh
[homepage-df]: https://github.com/gethomepage/homepage/blob/v2.5.0/Dockerfile
[homepage-docs]: https://github.com/gethomepage/homepage/blob/v2.5.0/docs/installation/index.md
[isso-df]: https://github.com/isso-comments/isso/blob/master/Dockerfile
[isso-views]: https://github.com/isso-comments/isso/blob/master/isso/views/comments.py
[guac-100]: https://github.com/apache/guacamole-client/blob/1.6.0/guacamole-docker/entrypoint.d/100-generate-guacamole-home.sh
[guac-500]: https://github.com/apache/guacamole-client/blob/1.6.0/guacamole-docker/entrypoint.d/500-generate-tomcat-catalina-base.sh
[guac-999]: https://github.com/apache/guacamole-client/blob/1.6.0/guacamole-docker/entrypoint.d/999-start-tomcat.sh
[guacd-df]: https://github.com/apache/guacamole-server/blob/1.6.0/Dockerfile
[guacd-entry]: https://github.com/apache/guacamole-server/blob/1.6.0/src/guacd-docker/bin/entrypoint.sh
[ab-entry]: https://github.com/ArchiveBox/ArchiveBox/blob/d1136d74cb8d70b067892088a11cd41add65a1d3/bin/docker_entrypoint.sh
[ab-urls]: https://github.com/ArchiveBox/ArchiveBox/blob/d1136d74cb8d70b067892088a11cd41add65a1d3/archivebox/core/urls.py
[novnc-df]: https://github.com/babraham123/docker-novnc/blob/master/Dockerfile
[novnc-entry]: https://github.com/babraham123/docker-novnc/blob/master/entrypoint.sh
[novnc-sup]: https://github.com/babraham123/docker-novnc/blob/master/supervisord.conf
[fe-df]: https://github.com/babraham123/finance-exporter/blob/main/Dockerfile
[go2rtc-df]: https://github.com/AlexxIT/go2rtc/blob/v1.9.14/docker/Dockerfile
[go2rtc-api]: https://github.com/AlexxIT/go2rtc/blob/v1.9.14/internal/api/api.go
[wy-piper]: https://github.com/rhasspy/wyoming-addons/blob/master/piper/run.sh
[wy-whisper]: https://github.com/rhasspy/wyoming-addons/blob/master/whisper/run.sh
[wy-oww]: https://github.com/rhasspy/wyoming-addons/blob/master/openwakeword/run.sh
[ppe-readme]: https://github.com/containers/prometheus-podman-exporter/blob/v2.0.0/README.md
[ppe-container]: https://github.com/containers/prometheus-podman-exporter/blob/v2.0.0/collector/container.go
[ne-systemd]: https://github.com/prometheus/node_exporter/blob/master/collector/systemd_linux.go
