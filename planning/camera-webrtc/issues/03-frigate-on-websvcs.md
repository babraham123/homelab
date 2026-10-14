# 03. Frigate with bundled go2rtc on websvcs; retire `src/services/go2rtc`

Status: ready-for-agent
Type: task
Repo: homelab
Source: maintainer request 2026-10-13; bundled go2rtc decided 2026-10-14
Blocked by: 01

## Problem

There's no recording or object detection, and no camera stream for HA. pve2's Coral TPU
and iGPU are set aside for this (`docs/architecture.md`) but unused. The standalone
`src/services/go2rtc/` is installed but inert:

- it has no streams;
- its WebRTC candidate points at homesvcs;
- 8555 isn't published.

Frigate's bundled go2rtc replaces it (maintainer decision 2026-10-14).

## Change

- **Retire the standalone go2rtc.** It's already out of the inventory and its case is
  commented out. Delete `src/services/go2rtc/`, the commented `go2rtc` case in
  `src/nodes/websvcs/install_svcs.sh`, and go2rtc in `docs/services.md`'s "not in use"
  line. If websvcs still has `/etc/containers/systemd/go2rtc.container` or
  `/etc/opt/go2rtc`, remove them (a manual step, listed in the PR).
- **`src/services/frigate/frigate.container.j2`**, following the other websvcs quadlets:
  - `Image=localhost/blakeblackshear/frigate:stable`, `ContainerName=frigate`,
    `HostName=nvr.{{ site.url }}`, `IP={{ websvcs.container_subnet }}.11`;
  - devices:
    - `AddDevice=/dev/dri` for decode;
    - the Coral: `/dev/apex_0` for PCIe, or the USB bus.

    Size `ShmSize` with Frigate's formula for one camera;
  - volumes:
    - `/etc/opt/frigate:/config`;
    - `/srv/media/frigate:/media/frigate` (HDD array);
    - a tmpfs at `/tmp/cache`;
  - `PublishPort=8555:8555/tcp` and `PublishPort=8555:8555/udp` only. **Never publish**:
    - 1984 (go2rtc API, no auth);
    - 5000 (Frigate's internal API, no auth);
    - 8554 (RTSP).

    Traefik reaches 8971 on the container network.
- **`src/services/frigate/config.yml.j2`:**
  - **`go2rtc:`.**
    - `streams`: `<name>` (main) and `<name>_sub` (sub) per entry in `cameras` (01).
      The camera password is the Podman secret `reolink_go2rtc_password`
      (`Secret=…,type=env,target=FRIGATE_RTSP_PASSWORD`), referenced as
      `{FRIGATE_RTSP_PASSWORD}` through Frigate's env substitution. Add it to
      `src/nodes/websvcs/secrets_template.yaml`.
    - `webrtc.candidates`:
      - `{{ websvcs.ip }}:8555`;
      - `stun:8555`, which makes go2rtc discover its public address for off-VPN peers.
    - `webrtc.ice_servers`:
      - `stun:{{ vpnsvcs.ip }}:3479`;
      - `turn:{{ vpnsvcs.ip }}:3479` with `username: webrtc` and the coturn credential
        (04).

      This replaces go2rtc's default Google/Cloudflare STUN.
  - **`cameras`.** Inputs `rtsp://127.0.0.1:8554/<name>` (role `record`) and
    `<name>_sub` (role `detect`), with `preset-rtsp-restream`. Every reader goes
    through go2rtc, so the camera sees one RTSP session.
  - **Detection and decode.** `detectors: coral` (`type: edgetpu`);
    `ffmpeg.hwaccel_args: preset-vaapi`.
  - **`mqtt`.** `homesvcs:8883`, TLS with the internal CA. Use a new Mosquitto user
    `frigate` with secret `mqtt_frigate_password`, passed the same way.
  - **Retention.** `record` and `snapshots` use a new `retention.frigate_days` in
    `vars.yml`. Suggest 7 days continuous and 30 for events.
  - **`auth`.**
    - Enable it on 8971, and set `proxy.header_map.user: Remote-User` so Authelia
      users are signed in.
    - Confirm in Frigate's docs that a request *without* the header (HA, leg 5) falls
      back to Frigate's own login rather than being trusted.
- **Traefik** (`src/nodes/websvcs/traefik/routes.yml.j2`): router `nvr`
  (`Host(nvr.SITE)`, the `*service` anchor with `authelia@file`) →
  `nvr.{{ site.url }}:8971`. 8971 serves TLS with a self-signed cert by default, so
  either use a `serversTransport` with `insecureSkipVerify` or turn Frigate's TLS off.
  Pick whichever Frigate supports cleanly.
- **Authelia `access_control`.** Add a `bypass` rule for `nvr.SITE` with
  `networks: [{{ homesvcs.ip }}/32]`, above the default rule.
- **Coral passthrough.** Confirm the Coral reaches websvcs per
  `docs/guides/proxmox.md.j2` "Coral TPU". If it doesn't, that's a manual step on pve2,
  noted here.
- **Wiring:**
  - `src/nodes/websvcs/inventory.yml`, under the services that need the media array:
    `frigate: {subdomain: nvr, uptime: frigate, upstream: ghcr.io/blakeblackshear/frigate:stable}`;
  - a `frigate` case in `src/nodes/websvcs/install_svcs.sh` that calls `require_media`;
  - a `docs/services.md` row and a Homepage entry;
  - exclude the recordings from the websvcs backup (recordings aren't backed up).

## Acceptance

- The Frigate UI loads at `https://nvr.SITE` after Authelia login.
- Live view plays over WebRTC from trusted WiFi. `chrome://webrtc-internals` shows the
  `{{ websvcs.ip }}:8555` host candidate selected.
- Detection runs on the Coral: `/api/stats` shows `coral` inference under 15 ms.
- The camera has one RTSP session (`ss -tn dst <camera>:554` on websvcs).
- Events appear on MQTT (`mosquitto_sub -t 'frigate/#'` on homesvcs).
- From mobile data, `nvr.SITE` redirects to Authelia. From homesvcs, `curl` reaches
  Frigate's login without Authelia.
- `ss -ltnp` / `-lunp` on websvcs show only 8555 newly bound on the host.

## Comments
