# 02. Shared device config, secrets.yaml, and backups of the config volume

Status: ready-for-human
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

- 2026-11-01 agent: implemented; live acceptance pending. Changed:
  - `src/services/esphome/common/base.yaml` replaces `config.yaml`, as written above.
  - `secrets_template.yaml`: `esphome_wifi_ssid`, `esphome_wifi_password`.
  - `esphome)` case: starts `esphomeconfig-volume.service`, installs `common/base.yaml` into the
    volume, and writes `secrets.yaml` (600, root) as `wifi_ssid` / `wifi_password` through `yq`,
    which quotes the values as YAML needs. It stops if either secret is empty. No other file in
    the volume is touched; a file later dropped from `common/` stays in the volume.
  - ESPHome reads `!secret` from the including file's directory first, then falls back to the
    main config's directory (`yaml_util.py` at 2026.10.1), so `common/base.yaml` finds the
    root `secrets.yaml`.
  - homesvcs guide: the install step names the two secrets and links the ESPHome guide.
  - No `secrets.yaml` is tracked or rendered: the install writes the only copy, into the volume.
  - Apply:

    ```bash
    tools/deploy_src.sh homesvcs pve1
    # Fill esphome_wifi_ssid and esphome_wifi_password (WiFiIoT's SSID and password)
    ssh -t manualadmin@pve1 'sudo /root/homelab-rendered/src/nodes/pve1/secret_update.sh homesvcs'
    ssh autoadmin@homesvcs install_esphome
    ```

  - Acceptance checks, on homesvcs as root:

    ```bash
    cfg=$(podman volume inspect -f '{{ .Mountpoint }}' systemd-esphomeconfig)
    stat -c '%a %U:%G %n' "$cfg/secrets.yaml"       # 600 root:root
    ls -A "$cfg" "$cfg/common"                     # secrets.yaml, common/base.yaml, devices
    # Dashboard: + New Device (e.g. test-esp32, ESP32), skip the install, add the two-line
    # packages include, Save. Then:
    podman exec esphome esphome config /config/test-esp32.yaml | grep -A6 '^wifi:'
    # fast_connect: true, domain: .iot.home.arpa, no "Secret ... not defined"
    sha256sum "$cfg/test-esp32.yaml" > /root/esphome-device.sha256
    /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh esphome
    sha256sum -c /root/esphome-device.sha256 && rm /root/esphome-device.sha256
    ```
