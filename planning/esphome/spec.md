# ESPHome on homesvcs

Run the ESPHome dashboard (Device Builder) on homesvcs. It builds firmware for ESP32 / ESP8266
devices on WiFiIoT and pushes updates over the air. Home Assistant controls the devices through
its ESPHome integration.

Maintainer request 2026-10-13. A disabled stub already exists:

- `src/services/esphome/` (quadlet and an empty `config.yaml`);
- the commented `esphome)` case in `src/nodes/homesvcs/install_svcs.sh`;
- the commented router in `src/nodes/homesvcs/traefik/routes.yml.j2`;
- the homepage entry;
- the OTA `ufw` rules in `docs/guides/homesvcs.md.j2`;
- `# Requires=esphome.service` in Home Assistant's quadlet.

`docs/services.md` lists it as "not in use".

## How it fits

```text
Mac (Chrome) ──HTTPS──▶ Traefik ─▶ esphome dashboard ──compile──▶ firmware
   │  first flash: Web Serial over USB, in the browser
   ▼
device on WiFiIoT ◀──OTA (3232/8266/2040)── esphome dashboard   (homesvcs → device)
device on WiFiIoT ◀──native API (6053)──── Home Assistant       (homesvcs → device)
```

Every connection is opened by homesvcs or the browser. Devices never connect into homesvcs. The
dashboard is only needed to flash or update a device; at runtime HA talks to the devices directly.
Onboarding steps: [docs/guides/esphome.md.j2](../../docs/guides/esphome.md.j2).

## Decisions

- **No USB on the server. The first flash goes from the Mac's browser.** The dashboard's
  Install → "Plug into this computer" compiles on homesvcs, then flashes over Web Serial in Chrome
  or Edge (not Safari or Firefox). Web Serial needs HTTPS, which Traefik already provides. After
  that, every update is OTA from the dashboard. For a device that's bricked or needs the boot
  button, the fallback is `uvx esphome run <node>.yaml` on the Mac. Passing USB through to the
  server is the wrong fit:
  - homesvcs runs on pve1, the fanless always-on box holding the trust roots. Plugging arbitrary
    boards into it is a security cost, and it isn't where the devices are.
  - A quadlet `AddDevice=` fails the container start when the device is missing. Hot-plugging into
    the VM (`qm set --usbN host=<vid>:<pid>`) then the container is a per-board chore.
  - Each board has a different USB serial chip: CP210x and CH340 show up as `ttyUSB*`, while the
    native USB of the ESP32-S2/S3/C3/C6 shows up as `ttyACM*`. Native-USB boards re-enumerate when
    they enter the bootloader, so one fixed device path doesn't cover them.
  - Many boards need the BOOT button held for the first flash anyway, so someone is at the device.
- **homesvcs reaches devices; devices don't reach homesvcs.** OTA and the native API are servers
  on the device. The stub's `PublishPort=3232/8266/2040/8892` lines and the guide's inbound IoT
  `ufw` rules point the wrong way and go. pfSense must allow homesvcs → WiFiIoT on TCP 6053, the
  OTA ports, and ICMP for the dashboard's status pings.
- **Fixed IPs with names under `iot.home.arpa`, no mDNS.**
  - WiFiIoT isn't in the pfSense mDNS bridge, which is for trusted VLANs only. So neither the
    dashboard nor HA can discover devices, and `ESPHOME_DASHBOARD_USE_PING=true` stays.
  - Each device gets a pfSense DHCP static mapping in .10–99, with its ESPHome name as the
    hostname. The WiFiIoT DHCP pool shrinks from .10–254 to .100–254, as LAN2's already is, so the
    mappings stay outside it.
  - The WiFiIoT DHCP domain is `iot.home.arpa`, and the DNS Resolver registers static mappings, so
    a device answers as `<name>.iot.home.arpa` from pfSense's existing Unbound.
    - `home.arpa` is the domain reserved for home networks (RFC 8375). It doesn't need a new DNS
      server or any public record.
    - The names aren't under the site domain, because Unbound's catch-all there answers every
      unlisted name with websvcs. A registered name inside it would likely still resolve to
      websvcs (unverified; 03 checks with `dig`).
  - `common/base.yaml` sets `wifi: domain: .iot.home.arpa`, so the dashboard reaches devices by
    name. HA adds them by name too.
- **The dashboard owns the device files; the repo owns the shared parts.**
  - Devices are created with "+ New Device" and edited in the dashboard. The wizard writes
    `<name>.yaml` with its own random API key, OTA password and fallback-AP password.
  - The repo holds only `common/base.yaml`, which each device includes in two lines: Wi-Fi,
    `fast_connect`, the domain, and the logger. It also holds the template for `secrets.yaml`.
  - Install writes those two files into the config volume and never touches device files.
  - Device files have no git history. Copy them into the repo by hand if that's ever wanted.
- **The config is a volume, backed up like HA's.** `esphomeconfig.volume` mounts at `/config`, as
  `hassconfig` does for HA, because device files are now state the dashboard writes. The install
  puts `common/` and `secrets.yaml` into it. Two backups cover it:
  - `backup.sh` stages it file by file with `stage_volume esphomeconfig`, excluding `.esphome`;
  - it's also inside the homesvcs VM image in PBS.

  Both run in the weekly Saturday backup.
- **`secrets.yaml` is rendered at install from the homesvcs SOPS bundle,** mode 600. ESPHome reads
  `!secret` only from that file, not from Podman secrets. It holds only `wifi_ssid` and
  `wifi_password`, the names the New Device wizard looks for, so the wizard fills them in without
  asking. Each device keeps its own API key in its YAML:
  - The key encrypts and authenticates Home Assistant's native-API connection. Without it, any
    device on WiFiIoT could read the board's sensors or flip its switches.
  - The key is stored readable in the board's flash. Per-device keys mean a board that's stolen
    and read out exposes only itself.
- **The build cache is its own volume, outside the backup.** Toolchains and PlatformIO packages
  land under `/config/.esphome` and run to gigabytes. `esphomebuild.volume` mounts over that path,
  so `stage_volume esphomeconfig` sees only an empty mount point there. The cache survives
  container re-creation, and losing it costs only a slower next compile.
- **Compiles are throttled.** pve1 is a 4-core N5105 that also runs pfSense. An ESP32 build pegs
  the CPU for minutes, and the first one also downloads toolchains. Cap the container with
  `PodmanArgs=--cpus=2` and set a memory limit, as in container-hardening/03.
- **Admin-only, behind Authelia.** The dashboard can read `secrets.yaml` and reflash every device.
  Its router uses `authelia@file` like the other homesvcs routers; auth/01's two-factor rule for
  admin subdomains covers it. Subdomain `iot`, as in the stub.
- **The ESPHome version is pinned in the inventory `upstream`,** like Home Assistant. A bump means
  recompiling and OTA-updating every device ("Update All"), so it is a deliberate step, not the
  nightly image update.
- **HA doesn't depend on the dashboard.** HA talks to the devices directly, so the
  `Requires=esphome.service` TODO goes.

## Risks to check in 01

- The Trivy gate may block the image: it's large and carries Python and toolchain dependencies
  (unverified).
- homesvcs's disk: the image plus a few GB of toolchains per chip family.
- WiFiIoT's SSID is hidden. ESPHome needs `fast_connect: true` to join a hidden network, so it
  goes in `common/base.yaml`.
- Whether a static mapping's name registers under the interface's DHCP domain (`iot.home.arpa`)
  or the system domain. 03 checks with `dig`.
- The LAN → WiFiIoT pfSense rules were copied from LAN and aren't documented per port. Confirm
  homesvcs actually reaches a WiFiIoT address on 6053.

## Out of scope

- Moving devices to MQTT instead of the native API.
- Blocking internet access for WiFiIoT, which ESPHome devices don't need. That belongs in
  router/.

## Issues

| # | Title | Status | Type | Blocked by |
| --- | --- | --- | --- | --- |
| [01](issues/01-install-dashboard.md) | Install the ESPHome dashboard on homesvcs | `ready-for-agent` | task | |
| [02](issues/02-device-configs-and-secrets.md) | Shared device config, `secrets.yaml`, and backups of the config volume | `ready-for-agent` | task | 01 |
| [03](issues/03-onboard-first-device.md) | Onboard the first device: browser flash, fixed IP, HA | `ready-for-human` | task | 02 |
