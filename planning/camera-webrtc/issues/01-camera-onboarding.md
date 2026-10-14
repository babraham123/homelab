# 01. Set up the Reolink camera on the IoT VLAN

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-13

## Problem

The camera has to join the network without gaining a cloud path or a way into the
trusted VLANs, and it has to expose an RTSP stream go2rtc can pull.

## Change

1. **Join the IoT VLAN.**
   - WiFi camera: the `machines` SSID (VLAN 11, `{{ wifi.iot.mask }}`).
   - Wired/PoE camera: an access port on WiredIoT (VLAN 21, `{{ wired.iot.mask }}`),
     which needs 07 first.

   Set it up with the Reolink app once over the local network. Don't create a Reolink
   cloud account.
2. **Static DHCP lease** in pfSense; add the camera to `vars.yml`:

   ```yaml
   cameras:
     - {name: front, model: "<model>", ip: 192.168.11.x}
   ```

   and to `vars.template.yml` with a placeholder IP.
3. **Firmware:** update to the latest from reolink.com before cutting internet access (02).
4. **Camera settings:**
   - Disable: UID/P2P, UPnP, cloud, push notifications, email/FTP, the HTTP port (keep
     HTTPS).
   - Enable: RTSP (:554) and ONVIF only if 05 needs it; set NTP to the pfSense IP.
   - Change the factory `admin` password.
5. **Users** (Reolink allows several):
   - `go2rtc`, guest/view-only, for RTSP;
   - `homeassistant`, admin role, for the Reolink integration (05).
   Store the passwords as `reolink_go2rtc_password` in websvcs's secrets and
   `reolink_ha_password` in homesvcs's (`src/nodes/<node>/secrets_template.yaml`,
   then `src/nodes/pve1/secret_update.sh <node>`).
6. **Stream check** from websvcs:
   `ffprobe 'rtsp://go2rtc:PASS@192.168.11.x:554/h264Preview_01_main'`. Record the main
   and sub stream paths in the ticket comments; models differ (`h264Preview_01_sub`,
   `h265Preview_01_main`).

## Acceptance

- The camera has a static IP on VLAN 11 or 21 and appears in `vars.yml`.
- `ffprobe` on websvcs reads both streams with the `go2rtc` user.
- The Reolink app shows P2P/UID, UPnP and cloud off.

## Comments
