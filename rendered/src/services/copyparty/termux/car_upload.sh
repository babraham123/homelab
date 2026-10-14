#!/data/data/com.termux/files/usr/bin/bash
# Uploads Car Scanner recordings (.brc) from the phone to copyparty's /car, through
# Authelia as car_uploader. Setup: docs/guides/car_upload.md.
# Usage:
#   ~/bin/car_upload.sh         every recording not yet sent, read through Shizuku's rish
#                               (Android blocks Termux from Android/data); run by
#                               termux-job-scheduler
#   ~/bin/car_upload.sh FILE    one file; ~/bin/termux-file-editor links here, so
#                               Share → Termux → Edit uploads a shared recording

set -euo pipefail

records=/sdcard/Android/data/com.ovz.carscanner/files/records
conf=~/.car_upload
# Names already uploaded, one per line
sent="${conf}/sent"
touch "$sent"

notify() {
  termux-notification --id car_upload --title "Car upload" --content "$1" 2> /dev/null || true
  echo "$1"
}

# Usage: upload FILE NAME
upload() {
  curl --silent --show-error --fail-with-body --retry 3 --max-time 120 \
    --netrc-file "${conf}/netrc" --upload-file "$1" \
    "https://files.janedoe.com/car/$(jq -rn --arg n "$2" '$n | @uri')" > /dev/null
}

if (( $# == 1 )); then
  name=$(basename "$1")
  [[ $name == *.brc ]] || { notify "not a .brc recording: ${name}"; exit 1; }
  if upload "$1" "$name"; then
    echo "$name" >> "$sent"
    notify "sent ${name}"
    rm -f "$1"
  else
    notify "failed ${name}, kept at $1"
    exit 1
  fi
  exit 0
fi

# Car Scanner writes a recording when it stops; skip any written in the last minute.
if ! list=$(rish -c "find ${records} -maxdepth 1 -type f -name '*.brc' -mmin +1"); then
  notify "rish failed: is Shizuku running? (restart it after a reboot)"
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
uploaded=0
failed=0
while IFS= read -r path; do
  [[ -n $path ]] || continue
  name=$(basename "$path")
  grep -qxF "$name" "$sent" && continue
  # rish runs the command through a shell; a quote in the name would break out of it.
  [[ $name != *"'"* ]] || { notify "skipped ${name}: quote in the name"; continue; }
  # A local copy gives curl a Content-Length and a file to retry from.
  if rish -c "cat '${records}/${name}'" > "${tmp}/${name}" && upload "${tmp}/${name}" "$name"; then
    echo "$name" >> "$sent"
    uploaded=$((uploaded + 1))
  else
    failed=$((failed + 1))
  fi
  rm -f "${tmp:?}/${name}"
done <<< "$list"

(( uploaded == 0 )) || notify "sent ${uploaded} recording(s)"
(( failed == 0 )) || { notify "${failed} upload(s) failed; the next run retries them"; exit 1; }
