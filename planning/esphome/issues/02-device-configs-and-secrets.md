# 02. Shared device config, secrets.yaml, and backups of the config volume

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-13; design in [spec.md](../spec.md)
Blocked by: 01

The dashboard owns device files. The repo owns only the shared package and `secrets.yaml`.
Onboarding follows [docs/guides/esphome.md.j2](../../../docs/guides/esphome.md.j2).

## Change

- Replace `src/services/esphome/config.yaml` (an empty TODO) with `common/base.yaml`, which every
  device includes:

  ```yaml
  wifi:
    ssid: !secret wifi_ssid
    password: !secret wifi_password
    # The IoT SSID is hidden
    fast_connect: true
    # pfSense registers DHCP static mappings under this domain
    domain: .iot.home.arpa
  logger:
  ```

  A wizard-made device keeps its own `api`, `ota` and `wifi: ap:` blocks. Adding

  ```yaml
  packages:
    base: !include common/base.yaml
  ```

  merges the rest in.
- `src/nodes/homesvcs/secrets_template.yaml`: add `esphome_wifi_ssid` and `esphome_wifi_password`.
- The `esphome)` install case:
  - install `common/` into the `esphomeconfig` volume path, as the `home_assistant)` case does
    with `hassconfig`;
  - render `secrets.yaml` there (mode 600) as `wifi_ssid` / `wifi_password` from the bundle via
    `get_secret.sh`;
  - never create, change or delete any other file in the volume.
- `docs/guides/homesvcs.md.j2`: link the ESPHome guide from the install step.

## Acceptance

- A device made with "+ New Device" validates with the two-line package include, with no missing
  `!secret`, and its config dump shows `fast_connect` and the domain.
- Reinstalling after a device exists leaves the device's YAML byte-identical.
- `secrets.yaml` is 600 and root-owned in the volume, and isn't in git or `rendered/`.

## Comments
