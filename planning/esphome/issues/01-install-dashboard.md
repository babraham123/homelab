# 01. Install the ESPHome dashboard on homesvcs

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-13; design in [spec.md](../spec.md)

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

- 2026-11-01 agent: implemented; live acceptance pending. Changed:
  - Inventory: `esphome` at `.10`, `subdomain: iot`, `uptime: esphome`, `upstream:
    docker.io/esphome/esphome:2026.10.1` (latest release). Also `admin: true`, which the spec's
    "Admin-only" decision implies but the change list left out: Authelia then asks for two
    factors on `iot.` from every network.
  - Quadlet: no `PublishPort`/`AddDevice`, `esphomeconfig.volume:/config` then
    `esphomebuild.volume:/config/.esphome`, `DropCapability=all`, `PodmanArgs=--cpus=2`,
    `Memory=2g` (quadlet key, present in Podman 5.8.2). 2g is an estimate for an ESP32 compile
    plus headroom, not a measurement: resize it from the peak recorded below.
  - `esphome)` install case (quadlet and both volumes), Traefik router and service on 6052,
    Homepage entry, HA's `Requires=esphome.service` TODO removed.
  - `backup.sh`: `excludes+=(--exclude=.esphome)` then `stage_volume esphomeconfig`, after
    `mqttdata` so the exclude applies to that volume alone; `esphomebuild` listed as not staged.
  - Docs: homesvcs guide (install line, OTA `ufw` rules replaced by the outbound note and the
    pfSense reachability check), `services.md` (homesvcs table, volume list), architecture diagram.
  - Apply (from the laptop; the deploy also installs homesvcs's dispatcher with the
    `install_esphome` case; the router's Unbound is a paste):

    ```bash
    tools/deploy_src.sh homesvcs secsvcs vpnsvcs websvcs pve1
    ssh autoadmin@secsvcs install_authelia      # iot. in the admin two-factor rule
    ssh autoadmin@secsvcs install_gatus         # the esphome endpoint
    ssh autoadmin@secsvcs install_victoriametrics  # Gatus metrics: esphome's host label
    ssh autoadmin@secsvcs install_olive_tin     # the install_esphome button
    ssh autoadmin@vpnsvcs install_haproxy       # SNI route for iot.
    ssh autoadmin@vpnsvcs install_headscale
    ssh autoadmin@websvcs install_homepage
    ssh autoadmin@homesvcs install_traefik      # the iot. router
    ssh autoadmin@homesvcs install_esphome      # image gate, quadlet, volumes
    # pfSense: paste the rendered src/services/dns/unbound.conf into the DNS Resolver's
    # Custom options (router guide), then Save and Apply
    ```

  - Acceptance checks, on homesvcs as root unless noted:

    ```bash
    systemctl status esphome --no-pager           # active; Trivy findings, if blocked, go here
    podman inspect -f '{{.HostConfig.NanoCpus}} {{.HostConfig.Memory}}' esphome
    # Browser: https://iot.<site> redirects to Authelia, asks for the second factor, then shows
    # the dashboard. curl from the laptop gets a 302 to auth.<site>, never the dashboard:
    curl -sI https://iot.<site>/ | head -n 3

    # Test compile of an empty ESP32 config; restart first so MemoryPeak covers only it
    cfg=$(podman volume inspect -f '{{ .Mountpoint }}' systemd-esphomeconfig)
    printf 'esphome:\n  name: compile-test\nesp32:\n  board: esp32dev\n' > "$cfg/compile-test.yaml"
    systemctl restart esphome
    time podman exec esphome esphome compile /config/compile-test.yaml
    systemctl show -p MemoryPeak esphome
    # Meanwhile, on pve1: other VMs stay responsive (qm list; ssh to secsvcs; pfSense UI)

    # Build cache in esphomebuild, config volume only YAML and an empty .esphome/
    du -sh "$(podman volume inspect -f '{{ .Mountpoint }}' systemd-esphomebuild)"
    find "$cfg" -mindepth 1 | head; find "$cfg/.esphome" -mindepth 1 | wc -l   # 0
    ```

    Then on pve1: `/root/homelab-rendered/src/nodes/pve1/collect_stage.sh homesvcs`, and
    `ls -A /root/backups/homesvcs/files/volumes/esphomeconfig` shows `compile-test.yaml` and no
    `.esphome`. Record the compile time and `MemoryPeak` here, and set `Memory=` from it.
