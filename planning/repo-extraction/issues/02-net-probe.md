# 02. Extract the network probe to net-probe

Status: resolved
Type: task
Repo: net-probe (new), homelab
Source: maintainer request 2026-10-25

## Change

- New repo babraham123/net-probe: `net_probe.py`, stdlib only, with the Jinja values (VictoriaMetrics
  query URL, plan speeds, targets, slots, busy checks) moved into a JSON config. README, example
  config, systemd unit and timer, the tests ported.
- Homelab: render the config from `vars.yml`; install the script on secsvcs at a pinned commit,
  checked by sha256.

## Answer

Done 2026-10-25 (net-probe `53d791b`; homelab branch `extract-net-probe`).

- **Repo:** `net_probe.py [--config PATH]`, default `/etc/net_probe/config.json`. Keys: `targets`,
  `isp.{down_mbps,up_mbps}`, `tests[]` (`speedtest` or `iperf`, `path`, `slots`, `busy` queries
  with `limit_bps`), `victoriametrics.{query_url, user, password_file | password_command}`, and
  optional `state_path`, `metrics_path`, `metric_prefix` (default `homelab`). A bad config fails at
  load with a message. 12 unittest cases: the 7 original ones plus config and CLI errors.
- **Homelab:** `src/base/net_probe/config.json.j2` replaces `net_probe.py.j2`; the password comes
  from `get_secret.sh` through `password_command`. The `net_probe` case installs
  `/usr/local/bin/net_probe` with `fetch_pinned`, beside the pinned Ookla CLI, and the unit runs it
  with `--config` on the rendered file, so a deploy updates the config in place.
  `tests/net_probe_test.sh` now checks only the rendered config.
- **Cutover:** the new version keeps samples in `state.json` without the metric prefix, so the
  old version's cached samples stop showing until each test runs again (up to 24 h for the VPS).
  Success times carry over, so no stale alert fires. 09 covers it.
