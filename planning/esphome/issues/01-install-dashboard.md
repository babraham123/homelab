# 01. Install the ESPHome dashboard on homesvcs

Status: ready-for-agent Type: task Repo: homelab Source: maintainer request 2026-10-13; design in
[spec.md](../spec.md)

## Change

- `src/nodes/homesvcs/inventory.yml`: add
  `esphome: {subdomain: iot, uptime: esphome, upstream: docker.io/esphome/esphome:<current
  release>}`. That gives the Unbound and HAProxy records, the Gatus check, and the image updater
  entry.
- `src/services/esphome/esphome.container.j2`:
  - drop the four `PublishPort` lines and the `AddDevice` TODO; the comment says why (devices are
    servers, the first flash is from the browser);
  - `Volume=esphomeconfig.volume:/config` in place of the `/etc/opt/esphome/config` bind mount,
    then `Volume=esphomebuild.volume:/config/.esphome` (two new `.volume` files, like
    `hassconfig.volume`);
  - `DropCapability=all`, from container-hardening's table. `ReadOnly` stays off, because compiles
    write under `/root`;
  - `PodmanArgs=--cpus=2` and a memory limit sized from a first ESP32 compile;
  - keep `ESPHOME_DASHBOARD_USE_PING=true`.
- `src/nodes/homesvcs/install_svcs.sh`: restore the `esphome)` case, installing the quadlet and
  both volumes. 02 fills the config volume.
- `src/nodes/homesvcs/traefik/routes.yml.j2`: enable the router and service on `iot.` port 6052.
- `src/services/home_assistant/home_assistant.container.j2`: delete the `Requires=esphome.service`
  TODO.
- `src/services/homepage/services.yaml.j2`: enable the entry at `iot.`.
- `docs/guides/homesvcs.md.j2`:
  - uncomment the install line;
  - replace the inbound OTA `ufw` rules with a note that devices never connect in;
  - add the pfSense check from the spec's risks.
- `docs/services.md`: move esphome from "not in use" into the homesvcs table at `.10`.
  `docs/architecture.md`: add ESPHome to homesvcs's box in the diagram.
- `src/nodes/homesvcs/backup.sh.j2`: the device files live only in `esphomeconfig`.
  - Stage it next to `z2mdb`:
    `excludes+=(--exclude=.esphome)` then `stage_volume esphomeconfig`.
  - The exclude guards against the build cache ever landing inside the config volume, for
    example if the `esphomebuild` mount is missing.
  - Fix the comment that says ESPHome configs come with `/etc/opt`.
  - Don't stage `esphomebuild`.
- `docs/services.md`: add `esphomeconfig` to the volume list under Storage and backups.
  `docs/guides/restore.md.j2`'s "Podman volume copy" step covers restoring it.

## Acceptance

- `install_svcs.sh esphome` passes the image gate and starts the container. If Trivy blocks the
  image, record the findings here instead.
- `https://iot.<site>` shows the dashboard after Authelia, and not before.
- A test compile of an empty ESP32 config finishes, with pve1's other VMs responsive throughout.
  Record its time and peak memory here.
- After the compile, `systemd-esphomebuild` holds the toolchains. `systemd-esphomeconfig` holds
  only YAML and an empty `.esphome/`.
- A `backup` run stages `volumes/esphomeconfig` with the test device's YAML, and nothing from
  `esphomebuild`.

## Comments
