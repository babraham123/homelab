#!/data/data/com.termux/files/usr/bin/bash
# Installs car_upload.sh on the phone and schedules it (docs/guides/car_upload.md).
# Needs termux-setup-storage, Shizuku running, its rish export in Download/rish and
# car_upload.sh in Download. Rerunning replaces the password and the schedule.
# Usage: bash ~/storage/downloads/car_upload_setup.sh

set -euo pipefail

dl=~/storage/downloads
conf=~/.car_upload

pkg install -y curl jq termux-api
mkdir -p ~/bin "$conf"

install -m 700 "${dl}/rish/rish" ~/bin/rish
sed -i 's/PKG/com.termux/' ~/bin/rish
install -m 400 "${dl}/rish/rish_shizuku.dex" ~/bin/rish_shizuku.dex
# The first call asks for approval in Shizuku
if [[ $(~/bin/rish -c id) != *'uid=2000(shell)'* ]]; then
  echo "rish isn't running as shell: is Shizuku started?" >&2
  exit 1
fi

install -m 700 "${dl}/car_upload.sh" ~/bin/car_upload.sh
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
