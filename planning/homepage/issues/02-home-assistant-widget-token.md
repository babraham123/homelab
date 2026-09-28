# 02. Get a Home Assistant long-lived access token for the homepage widget

Status: wontfix
Type: task
Repo: homelab
Source: maintainer request 2026-09-27

## Why

The `homeassistant` widget on the Home Assistant service in `src/homepage/services.yaml.j2`
is commented out because it needs a long-lived access token as `key`. With a token, it
would show people home, lights on and switches on, or the custom rows in the commented
block (apparent temperature, total power, energy today, switches on). The widget shows at
most four rows.

## Human step

1. In Home Assistant (`https://home.<site>`), open Profile → Security → Long-lived access
   tokens → Create token, named `homepage`. Consider a dedicated non-admin HA user, since
   the token has that user's full API access.
2. Record it: `ssh manualadmin@pve1`, then
   `sudo /root/homelab-rendered/src/pve1/secret_update.sh websvcs`, adding
   `dash_home_assistant_token`.

## Agent follow-up (after the token exists)

- Add `dash_home_assistant_token: ""` to `src/websvcs/secrets_template.yaml` under
  "Generated from ...", with a comment on where it comes from.
- Add `Secret=dash_home_assistant_token,type=env,target=HOMEPAGE_VAR_DASH_HOME_ASSISTANT_TOKEN`
  to `src/homepage/homepage.container.j2`.
- Uncomment the widget with `url: https://home.{{ site.url }}` and
  `key: {% raw %}{{HOMEPAGE_VAR_DASH_HOME_ASSISTANT_TOKEN}}{% endraw %}`, choosing which
  custom rows to keep. Check that the entity IDs exist in HA.
- Add the token step to `docs/guides/web_services.md.j2` "Setup homepage widgets".

## Comments

- 2026-09-27: wontfix. The widget calls HA server-side without an Authelia session, and
  `home.<site>` sits behind the `authelia` middleware (default policy deny), so the call
  would be refused. Neither workaround was worth it: opening `:8123` from websvcs, or an
  Authelia bypass for `^/api/`. The commented widget block was removed from
  `services.yaml.j2`, and no `hass_dash_token` secret was added.
