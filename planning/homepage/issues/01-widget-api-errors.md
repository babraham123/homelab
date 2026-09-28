# 01. Investigate the Proxmox, Google Calendar and weather widget API errors

Status: ready-for-agent
Type: research
Repo: homelab
Source: maintainer request 2026-09-27

## Problem

Three widgets on the homepage dashboard show API errors:

| Widget | Config | Secrets it uses |
|---|---|---|
| Proxmox | `src/homepage/proxmox.yaml.j2` (the per-service `proxmox` widgets in `services.yaml.j2` are commented out) | `DASH_PVE1_TOKEN` ← `dash_pve1_api_token` |
| Google Calendar (iCal) | `services.yaml.j2` → `Calendar` → `Home events` | `HOME_ICAL_URL` ← `home_ical_url` |
| Weather (Open-Meteo) | `src/homepage/widgets.yaml.j2` → `openmeteo` | `HOME_LATITUDE`, `HOME_LONGITUDE` ← `home_latitude`, `home_longitude` |

Podman secrets are mapped to env vars in `src/homepage/homepage.container.j2`.

## Leading hypothesis

All three break on env-var substitution. Homepage only substitutes placeholders named
`{{HOMEPAGE_VAR_*}}` or `{{HOMEPAGE_FILE_*}}` (https://gethomepage.dev/installation/docker/#using-environment-secrets).
The configs use `{{HOME_ICAL_URL}}`, `{{HOME_LATITUDE}}`, `{{DASH_PVE1_TOKEN}}` etc., so the
literal placeholder text is probably reaching the upstream APIs. That would explain all
three failing together. Confirm this before looking at other causes.

## Other causes to rule out

- Secret values: empty or stale on websvcs (`podman secret inspect --showsecret`; the
  template in `src/websvcs/secrets_template.yaml` defaults to `""`).
- Proxmox: `api_ro@pam!homepage` token missing, expired, or missing `PVEAuditor`; TLS
  verification of `pve1.<site>:8006` from inside the container; `proxmox.yaml` only has
  pve1 (no pve2).
- iCal: the Google "secret address" was reset, or the container can't make outbound HTTPS.
- Open-Meteo: outbound DNS/HTTPS from the websvcs container network.

## Steps

1. On websvcs: `podman logs homepage`, and the browser devtools response for each
   widget's `/api/widgets/...` or `/api/services/proxmox` call, to capture the real error.
2. `podman exec homepage env | grep -E 'HOME_|DASH_'` to check the secrets arrive.
3. Test the hypothesis: rename the env targets and placeholders to `HOMEPAGE_VAR_*`,
   re-render, redeploy (`install_homepage`), and check each widget.
4. For whatever still fails, test the upstream directly from inside the container
   (`curl`/`wget` against the PVE API with the token, the iCal URL, and
   `api.open-meteo.com`).

## Answer

_(Record the root cause per widget and the fix; open follow-up tickets if the fix is
not a one-liner.)_

## Comments

- 2026-09-27: step 3 implemented, not yet deployed or validated. In `src/homepage/`, every
  env target and placeholder is now `HOMEPAGE_VAR_<old name>` (for example
  `HOMEPAGE_VAR_HOME_LATITUDE`, `HOMEPAGE_VAR_DASH_PVE1_TOKEN`). The podman secret names
  are unchanged, so no secrets need recreating. Home Assistant's own `HOME_LATITUDE` /
  `HOME_LONGITUDE` are untouched. To validate: redeploy homepage on websvcs and check
  each widget. If one still errors, continue from step 1 for that widget.
- 2026-09-27: config review. The repo renders no active Proxmox widget: the service
  widgets in `services.yaml.j2` are commented out, and no service sets `proxmoxNode`.
  `proxmox.yaml` also lacks the required top-level node key (`pve1:`). A Proxmox error on
  the live dashboard therefore means the config deployed on websvcs has drifted from the
  repo. Before validating, diff `/etc/opt/homepage/config` against a fresh render.
- 2026-09-27: `proxmox.yaml` now uses the per-node key format (`pve1:`, `pve2:`), but it is
  still commented out because no service sets `proxmoxNode`.
- 2026-09-27: enabled the Proxmox 1, Proxmox 2 and PBS service widgets (PBS pinned to
  datastore `backup1`). They use the `api_ro@pam!homepage` tokens set up in
  `docs/guides/web_services.md` "Setup homepage widgets". Validate all three along with
  the calendar and weather widgets.
