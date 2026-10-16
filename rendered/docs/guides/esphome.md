# ESPHome devices

Guide to onboard a new ESP32 / ESP8266 board. First install the ESPHome dashboard on
[homesvcs](./homesvcs.md).

Devices live on WiFiIoT, each at a fixed IP and the name `<name>.iot.home.arpa`. The dashboard
(`https://iot.janedoe.com`) owns each device's YAML, builds its firmware and pushes updates.
Home Assistant talks to each device directly on port 6053, so the dashboard is only needed to
flash or update one. The repo owns only `common/base.yaml` (Wi-Fi and the domain) and
`secrets.yaml`.

## Once per board

You need: the board, a USB **data** cable (many are charge-only), and Chrome or Edge on the Mac.
Safari and Firefox can't flash.

1. **Create it.** In the dashboard: **+ New Device** → a name, lowercase with dashes
   (`office-co2`) → its board. Skip the install it offers.
2. **Include the shared config.** Open the device → **Edit**, add these lines, then **Save**:

   ```yaml
   packages:
     base: !include common/base.yaml
   ```

3. **Flash it over USB.** Plug the board into the Mac, then **Install** → **Plug into this
   computer**, and pick the serial port. If no port shows up, hold **BOOT** while plugging in, and
   keep holding it until the flash starts.
4. **Fix its address.** The board joins WiFiIoT with a pool address.
   - In pfSense, Status → DHCP Leases → its lease (the hostname is the device name) →
     **Add static mapping**.
   - Use the next free IP in 192.168.11.10–99 and the device name as the hostname.
   - Unplug and replug the board so it picks the address up.
5. **Check it.** The dashboard shows it **Online**; **Logs** → **Wirelessly** streams its logs.
6. **Add it to Home Assistant.** Settings → Devices & services → Add integration → ESPHome:
   - host is `<name>.iot.home.arpa`, port 6053;
   - the encryption key is in the dashboard, under the device's ⋮ → **Show API key**.

## Updates

- One device: **Edit** → **Save** → **Install** → **Wirelessly**.
- After an ESPHome version bump: **Update All**.

## Backups

Device YAML lives only in the `esphomeconfig` volume on homesvcs. The weekly backup (Saturday
02:00) copies it to `homesvcs/files/volumes/esphomeconfig/` in PBS, and it's also in the homesvcs
VM image. Restore it with [the volume-copy step](./restore.md). The build cache (`esphomebuild`)
isn't backed up: it rebuilds on the next compile. After onboarding several devices, don't wait
for Saturday: run `sudo systemctl start backup_orchestrator` on pve1 (see
[Maintenance](../maintenance.md#backups)).

## Troubleshooting

- **No serial port in Chrome.** Try another cable. A CH340 board on an old macOS needs the WCH
  driver.
- **Never comes Online.**
  - WiFiIoT is 2.4 GHz only.
  - Check that `dig +short <name>.iot.home.arpa` on homesvcs returns the mapped IP.
  - If the board can't join Wi-Fi at all, it opens a fallback hotspot named after the device. Its
    password is the `ap:` password in the device's YAML.
- **OTA times out.** homesvcs must reach WiFiIoT on TCP 3232 (ESP32) or 8266 (ESP8266).
- **The browser can't flash it at all.** Copy the config volume to the Mac and flash from there:

  ```bash
  ssh -t manualadmin@homesvcs 'sudo tar -C /var/lib/containers/storage/volumes/systemd-esphomeconfig/_data --exclude=.esphome -cf esphome.tar . && sudo chown manualadmin esphome.tar'
  scp manualadmin@homesvcs:esphome.tar . && ssh manualadmin@homesvcs 'rm esphome.tar'
  mkdir esphome && tar -C esphome -xf esphome.tar
  uvx esphome run esphome/<name>.yaml --device /dev/cu.usbserial-*
  rm -rf esphome esphome.tar
  ```
