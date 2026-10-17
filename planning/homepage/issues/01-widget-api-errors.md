# 01. Investigate the Proxmox, Google Calendar and weather widget API errors

Status: ready-for-human
Type: research
Repo: homelab
Source: maintainer request 2026-09-27

## Problem

Three widgets on the homepage dashboard show API errors:

| Widget | Config | Secrets it uses |
| --- | --- | --- |
| Proxmox | `src/services/homepage/proxmox.yaml.j2` (the per-service `proxmox` widgets in `services.yaml.j2` are commented out) | `DASH_PVE1_TOKEN` ← `dash_pve1_api_token` |
| Google Calendar (iCal) | `services.yaml.j2` → `Calendar` → `Home events` | `HOME_ICAL_URL` ← `home_ical_url` |
| Weather (Open-Meteo) | `src/services/homepage/widgets.yaml.j2` → `openmeteo` | `HOME_LATITUDE`, `HOME_LONGITUDE` ← `home_latitude`, `home_longitude` |

Podman secrets are mapped to env vars in `src/services/homepage/homepage.container.j2`.

## Leading hypothesis

All three break on env-var substitution. Homepage only substitutes placeholders named
`{{HOMEPAGE_VAR_*}}` or `{{HOMEPAGE_FILE_*}}`
(<https://gethomepage.dev/installation/docker/#using-environment-secrets>). The configs use
`{{HOME_ICAL_URL}}`, `{{HOME_LATITUDE}}`, `{{DASH_PVE1_TOKEN}}` etc., so the literal placeholder
text is probably reaching the upstream APIs. That would explain all three failing together. Confirm
this before looking at other causes.

## Other causes to rule out

- Secret values: empty or stale on websvcs (`podman secret inspect --showsecret`; the template in
  `src/nodes/websvcs/secrets_template.yaml` defaults to `""`).
- Proxmox: `api_ro@pam!homepage` token missing, expired, or missing `PVEAuditor`; TLS verification
  of `pve1.<site>:8006` from inside the container; `proxmox.yaml` only has pve1 (no pve2).
- iCal: the Google "secret address" was reset, or the container can't make outbound HTTPS.
- Open-Meteo: outbound DNS/HTTPS from the websvcs container network.

## Steps

1. On websvcs: `podman logs homepage`, and the browser devtools response for each widget's
   `/api/widgets/...` or `/api/services/proxmox` call, to capture the real error.
2. `podman exec homepage env | grep -E 'HOME_|DASH_'` to check the secrets arrive.
3. Test the hypothesis: rename the env targets and placeholders to `HOMEPAGE_VAR_*`, re-render,
   redeploy (`install_homepage`), and check each widget.
4. For whatever still fails, test the upstream directly from inside the container (`curl`/`wget`
   against the PVE API with the token, the iCal URL, and `api.open-meteo.com`).

## Answer

Source pinned to homepage `v2.5.0` (current `latest`; the quadlet runs
`localhost/gethomepage/homepage:latest`, which the image updater tracks, so websvcs could be on
`v2.4.0`). The relevant files are identical in both
tags apart from the PBS `since` change noted below.

### Substitution (confirmed by source)

- Only `{{HOMEPAGE_VAR_X}}` (value) and `{{HOMEPAGE_FILE_X}}` (file contents) are replaced, as a
  raw-text `replaceAll` before YAML parsing
  ([config.js#L8-L10](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/config/config.js#L8-L10),
  [#L53-L81](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/config/config.js#L53-L81);
  [docs](https://gethomepage.dev/installation/docker/#using-environment-secrets)).
- Substituted files: `settings.yaml`
  ([config.js#L88](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/config/config.js#L88)),
  `services.yaml`
  ([service-helpers.js#L58](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/config/service-helpers.js#L58)),
  `widgets.yaml`
  ([widget-helpers.js#L12](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/config/widget-helpers.js#L12)),
  `proxmox.yaml`
  ([proxmox.js#L11](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/config/proxmox.js#L11)),
  plus `docker.yaml` and `kubernetes.yaml`.
- Because substitution is textual, `latitude: <value>` parses as a YAML number (`CORE_SCHEMA`,
  [yaml.js#L4-L8](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/config/yaml.js#L4-L8)).
  An empty secret parses as `null`.
- Old placeholders like `{{HOME_LATITUDE}}` were not substituted, so js-yaml 5.4.3 read them as a
  flow mapping `{"[object Object]": null}` (reproduced locally). That explains each widget failing
  on its own instead of `services.yaml` failing to load.
- Repo state: every placeholder in `src/services/homepage/` and every `Secret=...,type=env,target=`
  in `homepage.container.j2` now uses `HOMEPAGE_VAR_*`. No old-style placeholders remain. Secret
  names match `src/nodes/websvcs/secrets_template.yaml`.
- Secret values arrive without a trailing newline (`get_secret_by_id.sh` runs `head -c -1`).

### Per widget

| Widget | Root cause | Status | Fix | In repo? |
| --- | --- | --- | --- | --- |
| Weather (Open-Meteo) | Unsubstituted `{{HOME_LATITUDE}}` became an object, so the query sent `latitude=[object Object]`. Open-Meteo returned `{"error":true}` and the widget showed an error ([openmeteo.jsx#L18-L22](https://github.com/gethomepage/homepage/blob/v2.5.0/src/components/widgets/openmeteo/openmeteo.jsx#L18-L22), [api/widgets/openmeteo.js#L3-L9](https://github.com/gethomepage/homepage/blob/v2.5.0/src/pages/api/widgets/openmeteo.js#L3-L9)). The fetch is server-side, so container egress to `api.open-meteo.com` is still needed. `cachedRequest` caches failures for `cache` minutes ([http.js#L85-L109](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/proxy/http.js#L85-L109)). | Mechanism confirmed by source; fix needs live check | `HOMEPAGE_VAR_HOME_LATITUDE/LONGITUDE` | Yes (afe41e3) |
| Calendar (iCal) | Same: `url` became an object, so `integration.url.includes(...)` threw and returned 500 ([calendar/proxy.js#L14-L26](https://github.com/gethomepage/homepage/blob/v2.5.0/src/widgets/calendar/proxy.js#L14-L26)). The fetch is server-side and the URL is removed from the client payload ([service-helpers.js#L667-L678](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/config/service-helpers.js#L667-L678)). Remaining error modes: empty secret → 403 "No integration URL specified"; secret address reset → upstream 404 is passed through; a feed with zero events also shows as an error ("ical: 'Home': No events found", [ical.jsx#L67-L70](https://github.com/gethomepage/homepage/blob/v2.5.0/src/widgets/calendar/integrations/ical.jsx#L67-L70), [#L161-L162](https://github.com/gethomepage/homepage/blob/v2.5.0/src/widgets/calendar/integrations/ical.jsx#L161-L162)). Config shape matches the [docs](https://gethomepage.dev/widgets/services/calendar/). | Mechanism confirmed by source; fix needs live check | `HOMEPAGE_VAR_HOME_ICAL_URL` | Yes |
| Proxmox 1 / 2, PBS | Removed 2026-10-12 (service widgets, `dash_*` secrets, `proxmox.yaml`, guide section). Research notes in case they return: PVE and PBS both intersect token ACLs with the user's ([PVE](https://pve.proxmox.com/pve-docs/chapter-pveum.html#pveum_tokens), [PBS](https://pbs.proxmox.com/docs/user-management.html#api-token-permissions)), so the user also needs `PVEAuditor` / `Audit`; the old guide granted it to the token only. PBS tokens are created in the PBS UI. | n/a | Removed | Yes |

### Other repo findings (not edited)

- Open-Meteo `latitude`/`longitude` are not private options, so they reach every browser
  ([widget-helpers.js#L34-L43](https://github.com/gethomepage/homepage/blob/v2.5.0/src/utils/config/widget-helpers.js#L34-L43)).
  Keeping them as podman secrets protects only the repo, not the dashboard's viewers.
- The image tracks upstream `:latest`, so the running version is whatever the image updater last
  loaded. Consider pinning a tag.

### Live validation still required (websvcs)

```bash
# 1. Config drift and image version
cd /root/homelab-rendered/src && for f in services/homepage/*.yaml; do diff -q "$f" /etc/opt/homepage/config/"$(basename "$f")"; done
podman image inspect localhost/gethomepage/homepage:latest --format '{{index .Labels "org.opencontainers.image.version"}}'
# 2. Env vars present and non-empty (prints length only)
podman exec homepage sh -c 'for v in $(env | grep -o "^HOMEPAGE_VAR_[A-Z0-9_]*"); do echo "$v len=$(printenv $v | wc -c)"; done'
# 3. Each widget through homepage's own proxy (same path the browser uses)
H=http://10.11.0.9:3000
curl -s "$H/api/services/proxy?group=Calendar&service=Home%20events&index=0&endpoint=Home" | head -c 300; echo
podman exec homepage node -e 'fetch("https://api.open-meteo.com/v1/forecast?latitude="+process.env.HOMEPAGE_VAR_HOME_LATITUDE+"&longitude="+process.env.HOMEPAGE_VAR_HOME_LONGITUDE+"&current_weather=true").then(r=>console.log(r.status))'
podman logs --since 1h homepage 2>&1 | grep -iE 'error|proxmox|calendar|openmeteo' | tail -30
# 4. Drop the removed widgets' secrets: on pve1, delete dash_pve1_api_token, dash_pve2_api_token
#    and dash_pbs2_api_token in the sops editor (secret_update.sh recreates all podman secrets)
sudo /root/homelab-rendered/src/nodes/pve1/secret_update.sh websvcs
# 5. Revoke the unused tokens
pveum user token remove api_ro@pam homepage                  # pve1 and pve2
proxmox-backup-manager user delete-token api_ro@pam homepage # PBS
```

## Comments

- 2026-09-27: step 3 implemented, not yet deployed or validated. In `src/services/homepage/`, every
  env target and placeholder is now `HOMEPAGE_VAR_<old name>` (for example
  `HOMEPAGE_VAR_HOME_LATITUDE`, `HOMEPAGE_VAR_DASH_PVE1_TOKEN`). The podman secret names are
  unchanged, so no secrets need recreating. Home Assistant's own `HOME_LATITUDE` / `HOME_LONGITUDE`
  are untouched. To validate: redeploy homepage on websvcs and check each widget. If one still
  errors, continue from step 1 for that widget.
- 2026-09-27: config review. The repo renders no active Proxmox widget: the service widgets in
  `services.yaml.j2` are commented out, and no service sets `proxmoxNode`. `proxmox.yaml` also lacks
  the required top-level node key (`pve1:`). A Proxmox error on the live dashboard therefore means
  the config deployed on websvcs has drifted from the repo. Before validating, diff
  `/etc/opt/homepage/config` against a fresh render.
- 2026-09-27: `proxmox.yaml` now uses the per-node key format (`pve1:`, `pve2:`), but it is still
  commented out because no service sets `proxmoxNode`.
- 2026-09-27: enabled the Proxmox 1, Proxmox 2 and PBS service widgets (PBS pinned to datastore
  `backup1`). They use the `api_ro@pam!homepage` tokens set up in `docs/guides/web_services.md`
  "Setup homepage widgets". Validate all three along with the calendar and weather widgets.
- 2026-10-12: research pass; findings in Answer.
- 2026-10-12: removed the Proxmox 1, Proxmox 2 and PBS widgets and their secrets. Weather and
  calendar fixes are in; close once the live validation above shows both loading.
