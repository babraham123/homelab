# 04. Auto-upload Car Scanner Pro recordings from the phone with Termux

Status: ready-for-agent Type: task Repo: homelab Source: maintainer request 2026-09-26
(<https://wiki.termux.com/wiki/Intents_and_Hooks>); research 2026-10-12 Blocked by: 01

## Problem

Manual uploads through the copyparty web UI work (01), but exporting from Car Scanner and uploading
after every drive is a chore.

## Findings

- Car Scanner has no auto-export. CSV/BRC export goes through the Share sheet only, and the app
  documents no intents, Tasker actions or folder sync
  ([carscanner.info/records](https://www.carscanner.info/records/)).
- It does save every recording on its own: a `.brc` file, written when the adapter disconnects or
  recording is switched off ("Data recording" is on by default). The files live in
  `/sdcard/Android/data/com.ovz.carscanner/files/records/`
  ([rav4world](https://www.rav4world.com/threads/how-to-view-carscanner-data-on-a-full-size-desktop-computer.335453/)).
  03 parses BRC directly; the format is documented there.
- Android 11+ blocks apps, Termux included, from reading `Android/data`. The `shell` UID (adb) can
  still read it, and [Shizuku](https://shizuku.rikka.app/) + `rish` gives Termux a shell-UID process
  without root
  ([setup on Android 14](https://oddity.oddineers.co.uk/2024/01/14/termux-shizuku-and-rish-configuration-for-android-14/)).
  Non-root Shizuku has to be restarted after each phone reboot over wireless debugging
  ([Shizuku#462](https://github.com/RikkaApps/Shizuku/discussions/462)).
- Car Scanner only records the sensors on the open screen. Keep one dashboard/list screen with the
  sensors 03 charts open while driving.
- `HeaderAuthorization` with `Basic` is already enabled on Authelia's forward-auth endpoint
  (`src/services/authelia/configuration.yml.j2`), so a non-interactive upload identity needs only a
  user and an access rule.

## Change

- **Upload identity:**
  - LLDAP user `car_uploader`, not in `authelia_gen_access`.
  - Authelia rule above the generic `two_factor` rule: domain `files.{{ site.url }}`,
    `subject: user:car_uploader`, `methods: [PUT, POST]`, `resources: ['^/car/']`,
    `policy: one_factor`. Every other request from that user falls to `default_policy: deny`.
  - copyparty: `car_uploader` gets `w` (write-only) on `/car`.
  - Check that copyparty ignores the forwarded `Authorization: Basic` header when `idp-h-usr` is
    set; otherwise strip it in Traefik.
- **`src/services/copyparty/termux/car_upload.sh`**:
  1. `rish -c 'ls /sdcard/Android/data/com.ovz.carscanner/files/records'`; skip names listed in
     `~/.car_upload/sent`.
  2. `rish -c 'cat …/<f>.brc' | curl -fsS --netrc-file ~/.car_upload/netrc -T - https://files.SITE/car/<f>.brc`.
  3. Append the name to `sent` on success.
- **Triggers:** `termux-job-scheduler --period-ms 900000 --network unmetered` and, optionally,
  Tasker (Termux:Tasker) on Bluetooth disconnect from the vLinker, which is when the `.brc` gets
  written.
- **`docs/guides/car_upload.md`**: phone setup (Termux, Termux:API, Shizuku + `rish`, netrc,
  scheduler, restarting Shizuku after a reboot).
- **`docs/security.md`**: record `car_uploader` as a one-factor credential stored on the phone,
  limited to `PUT`/`POST` on `files.SITE/car/`.
- **Fallback** if Shizuku proves unreliable: Share → BRC → Termux, where
  `~/bin/termux-file-editor <path>` runs the same `curl`. That costs one tap per trip.

Out of scope: a WiCAN Pro dongle would push OBD data to MQTT over home Wi-Fi with no phone involved
([meatpi](https://www.crowdsupply.com/meatpi-electronics/wican-pro/updates/wican-firmware-update-improved-support-for-home-assistant)),
but it would need a different pipeline from 03.

## Acceptance

- After a drive, the recording appears in `/var/opt/copyparty/data/car/` within one scheduler
  period of the phone joining home Wi-Fi, with no taps.
- Each file is uploaded once, and nothing is lost when an upload fails while websvcs is down.
- `car_uploader` can't list, read or delete anything, can't write outside `/car`, and can't log in
  to any other service.

## Comments
