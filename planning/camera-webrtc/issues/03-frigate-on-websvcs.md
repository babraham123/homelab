# 03. Frigate with bundled go2rtc on websvcs; retire `src/services/go2rtc`

Status: ready-for-human
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
    - `webrtc.ice_servers`: `stun:stun.cloudflare.com:3478` only, replacing go2rtc's
      defaults so one provider sees the home IP's STUN requests. Headscale's STUN on
      vpnsvcs:3478 can't stand in: it only answers requests carrying Tailscale's
      SOFTWARE attribute.

      **No `turn:` entry.** There's no TURN server (04, wontfix), and Frigate's
      `GET /api/config` returns `go2rtc.webrtc.ice_servers` as written to every
      logged-in Frigate user (Frigate 0.16/0.17, `frigate/api/app.py`), so a TURN
      credential here would leak.
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

2026-11-01, implemented; ready for the apply and acceptance checks.

What changed:

- `src/services/go2rtc/` deleted, with its commented install case, the guide line and the
  "not in use" mention.
- `src/services/frigate/`: `frigate.container.j2` (`.11`, `nvr.SITE`, `/dev/dri`, `/dev/apex_0`,
  `ShmSize=128m`, a 1 GB tmpfs cap at `/tmp/cache`, only 8555 tcp/udp published) and
  `config.yml.j2` (streams, candidates and Cloudflare STUN from `cameras`; Coral `device: pci`;
  `preset-vaapi`; detection on; MQTT over TLS; retention from `retention.frigate_days`).
- Inventory entry under the media services, a `frigate` case (`require_media`, dies without
  `/dev/apex_0`), Traefik router `nvr` → `http://nvr.SITE:8971/`, Authelia bypass for
  `{{ homesvcs.ip }}/32`, Homepage entry, `docs/services.md` row, Gatus via `uptime: frigate`.
- `vars.template.yml`: `cameras` (one placeholder) and `retention.frigate_days`
  (`continuous: 7`, `events: 30`). Optional per-camera `main`/`sub` RTSP paths override
  `h264Preview_01_main`/`_sub`.
- `reolink_go2rtc_password` in websvcs's `secrets_template.yaml`.
- Backup: Frigate's DB and model cache are excluded; recordings live on the media array,
  which isn't staged.
- `install_network.sh`: on websvcs, a ufw route rule for 8555 (tcp+udp). Published ports are
  DNATed, so without it ufw's forward policy drops them, and `install_network.sh` resets ufw
  each run, so a manual rule wouldn't survive.

Deviations from the ticket, from Frigate's docs and v0.18.2 source:

- **No `proxy.header_map`.** Frigate reads it only when `auth.enabled: false` (reference
  config: "Only used if Frigate's auth is disabled"; `frigate/api/auth.py` `auth()`). With auth
  on, identity comes only from Frigate's JWT (cookie or Bearer); without one it answers 401
  with `location: /login`, so a request without `Remote-User` does fall back to Frigate's
  login. With auth off, a request without the header is let in as user `viewer` with
  `default_role`, so HA's Authelia bypass would be an open door. Auth stays on and
  `header_map` is left out as dead config: Authelia users sign in twice (Authelia, then
  Frigate).
- **No `mqtt_frigate_password`.** Mosquitto has no password users here:
  `require_certificate true` and `use_identity_as_username true`, like zigbee2mqtt and HA.
  Frigate gets a client cert `CN=nvr.SITE` from the private CA (pve1's key/cert scripts, websvcs
  `install_keys`/`install_certs` → `/etc/opt/frigate/certificates/`). Frigate's reference says
  not to set user/password with a client cert.
- **Frigate TLS off** (`tls.enabled: false`, documented for reverse proxies) rather than a
  `serversTransport` with `insecureSkipVerify`: the hop is Traefik → container on websvcs's
  own bridge, like every other backend, and skip-verify adds a transport that authenticates
  nothing. `auth.cookie_secure: true`, since browsers only see HTTPS.
- **Loopback binds** for 5000 (`networking.listen.internal: 127.0.0.1:5000`; every request on
  it is admin), go2rtc's API (`127.0.0.1:1984`) and RTSP (`127.0.0.1:8554`): other containers
  on websvcs's bridge can't reach them. Frigate's nginx, healthchecks and ffmpeg use 127.0.0.1.
- IP via the inventory (`ip: 11`, `inv.addr.websvcs.frigate`), as the other quadlets do now.

Other Frigate-docs findings:

- shm: per frame `(w × h × 1.5 + 270480) / 1048576` MB at the detect resolution, 25 frames
  per camera minimum (Frigate warns under 20, uses up to 50), plus 50 MB for logs and nginx.
  One 720p camera: 90 MB.
- Coral: PCIe `/dev/apex_0` with `device: pci`; USB would be `/dev/bus/usb` with
  `device: usb`. websvcs's is PCIe (`1ac1:089a`).
- Secrets: `{FRIGATE_*}` substitution works in go2rtc stream URLs (`create_config.py` formats
  them with `FRIGATE_` env vars and `/run/secrets/FRIGATE_*`); go2rtc's own `${VAR}` is
  disabled in streams. The password goes in the URL unescaped: letters and digits only.
- `detect.enabled` defaults to false; set true.
- `/` on 8971 serves the UI without auth, so Gatus's default `/` check works.

Apply (nothing here has been run):

1. `vars.yml`: add `cameras` (from 01) and `retention.frigate_days`; renders and
   `tests/vars_test.sh` fail until both are there.
2. Secrets: add `reolink_go2rtc_password`, then
   `sudo /root/homelab-rendered/src/nodes/pve1/secret_update.sh websvcs` on pve1.
3. Coral and iGPU on websvcs:
   `lspci -nn | grep -e 089a -e VGA; ls -l /dev/apex_0 /dev/dri/by-path/`.
   If `/dev/apex_0` is missing: pve2 passthrough per `docs/guides/proxmox.md` "Coral TPU", then
   `install_coral.sh` per `docs/guides/gpu.md`. `preset-vaapi` uses `/dev/dri/renderD128`;
   check it's the iGPU, not the P4 (`vainfo --display drm --device /dev/dri/renderD128`).
4. Deploy: `tools/deploy_src.sh websvcs secsvcs vpnsvcs`.
5. Client cert (rotates every internal key and cert; restart the secure services after):
   `sudo /root/homelab-rendered/src/nodes/pve1/certificates/self_signed_key_gen.sh`, then
   `self_signed_cert_gen.sh`.
6. Remove the old go2rtc on websvcs:
   `sudo systemctl stop go2rtc; sudo rm -f /etc/containers/systemd/go2rtc.container;`
   `sudo rm -rf /etc/opt/go2rtc; sudo systemctl daemon-reload`, and
   `sudo podman image rm localhost/alexxit/go2rtc:latest` if present.
7. websvcs: `sudo /root/homelab-rendered/src/base/podman/install_network.sh`, then
   `ssh autoadmin@websvcs install_traefik`, `install_homepage`, `install_frigate`. The image
   is large: if the scan gate blocks it, add a `.trivyignore`.
8. `ssh autoadmin@secsvcs install_authelia` and `install_gatus`;
   `ssh autoadmin@vpnsvcs install_headscale` for the `nvr` MagicDNS record.
9. Frigate's first start logs a generated admin password:
   `sudo journalctl -u frigate | grep -i password`. Create a Frigate user for HA (05).
10. homesvcs: `sudo ufw status | grep 8883`. The homesvcs guide adds the 8883 rules by hand
    and `install_network.sh` resets ufw, so they may be gone; re-add them if so.

Verify:

- `curl -sI https://nvr.SITE/api/version` from homesvcs: 401 from Frigate, no Authelia
  redirect. From mobile data: a redirect to `auth.SITE`.
- Coral: `sudo podman exec frigate curl -s http://127.0.0.1:5000/api/stats | jq .detectors`
  (inference under 15 ms).
- One RTSP session:
  `sudo nsenter -t "$(sudo podman inspect -f '{{.State.Pid}}' frigate)" -n ss -tn dst CAM_IP:554`
  (go2rtc's socket is in the container's namespace, not the host's).
- MQTT, on homesvcs:
  `sudo podman run --rm --network host -v /etc/opt/home_assistant/certs:/c:ro
  localhost/library/eclipse-mosquitto:latest mosquitto_sub -h mqtt.SITE -p 8883
  --cafile /c/ca.chain.pem --cert /c/client.pem --key /c/client.key -t 'frigate/#' -v -C 5`.
- `sudo ss -ltnp; sudo ss -lunp` on websvcs: only 8555 new on the host.
- `chrome://webrtc-internals` on trusted WiFi: the `{{ websvcs.ip }}:8555` host candidate.

2026-11-01: Frigate is parked as "not in use" until the setup is done: out of websvcs's
inventory, with its install case, Traefik router, Authelia bypass, Homepage entry and 8555 ufw
rule commented out. Re-enabling them is the first step of the apply list. Apply step 10 is
fixed: `install_network.sh` now adds homesvcs's 8883 route rule.
