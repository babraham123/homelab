#!/data/data/com.termux/files/usr/bin/bash
# Installs car_upload.sh on the phone and schedules it (docs/guides/car_upload.md).
# Needs Shizuku running, rish set up in ~/bin, and car_upload.sh pushed to $staging, which
# only adb and Shizuku's shell user can read or write. Rerunning replaces the password and
# the schedule.
# Usage: bash ~/car_upload_setup.sh

set -euo pipefail

staging=/data/local/tmp/car_upload
conf=~/.car_upload

pkg install -y curl jq termux-api
mkdir -p "$conf"

if [[ $(~/bin/rish -c id) != *'uid=2000(shell)'* ]]; then
  echo "rish isn't running as shell: is Shizuku started?" >&2
  exit 1
fi

~/bin/rish -c "cat ${staging}/car_upload.sh" > ~/bin/car_upload.sh
chmod 700 ~/bin/car_upload.sh
# Share >> Termux >> Edit runs termux-file-editor: the fallback without Shizuku
ln -sf car_upload.sh ~/bin/termux-file-editor

read -rsp "car_uploader password: " password
echo
(
  umask 077
  printf 'machine files.janedoe.com login car_uploader password %s\n' "$password" \
    > "${conf}/netrc"
)

termux-job-scheduler --job-id 1 --script ~/bin/car_upload.sh --period-ms 900000 \
  --network unmetered --persisted true
termux-job-scheduler --pending

# Shizuku keeps running once started; adb over Wi-Fi isn't needed until the next reboot.
if [[ $(~/bin/rish -c 'settings get global adb_wifi_enabled') == 1 ]]; then
  echo "Turn off Developer options >> Wireless debugging"
fi
