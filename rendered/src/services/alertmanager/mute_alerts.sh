#!/bin/bash
# Mutes Alertmanager notifications (the ntfy push and both alert emails) with one silence
# that ends on its own, so nothing is redeployed. mute_alerts_* covers everything but
# Watchdog, which stays unmuted or the VPS's deadman check would report the pipeline down.
# mute_backup_run covers only the hosts the weekly backup run powers on and off (pve2 and
# its VMs), for 3 h: the rules skip websvcs while pve2 is absent, not while it boots or
# shuts down. A new mute replaces this script's last one of the same kind rather than
# stacking, and unmuting leaves silences made in the UI alone. deadman, cert_notifier and
# Proxmox mail don't go through Alertmanager and aren't muted.
# Usage:
#   src/services/alertmanager/mute_alerts.sh mute_alerts_1h|mute_alerts_4h|mute_alerts_24h
#   src/services/alertmanager/mute_alerts.sh unmute_alerts
#   src/services/alertmanager/mute_alerts.sh mute_backup_run|unmute_backup_run

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

# Alertmanager rejects a silence whose matchers all match an empty label, so the negative
# Watchdog matcher needs the catch-all beside it.
everything='[{"name": "alertname", "value": ".+", "isRegex": true, "isEqual": true},
  {"name": "alertname", "value": "Watchdog", "isRegex": false, "isEqual": false}]'
backup_hosts='[{"name": "host", "value": "pve2|websvcs|devtop|gaming", "isRegex": true, "isEqual": true}]'
case ${1:-} in
  mute_alerts_1h) hours=1 creator=mute_alerts matchers=$everything what="Every notification" ;;
  mute_alerts_4h) hours=4 creator=mute_alerts matchers=$everything what="Every notification" ;;
  mute_alerts_24h) hours=24 creator=mute_alerts matchers=$everything what="Every notification" ;;
  unmute_alerts) hours="" creator=mute_alerts ;;
  mute_backup_run) hours=3 creator=backup_run matchers=$backup_hosts what="pve2 and its VMs" ;;
  unmute_backup_run) hours="" creator=backup_run ;;
  *) die "usage: $0 mute_alerts_1h|mute_alerts_4h|mute_alerts_24h|unmute_alerts|mute_backup_run|unmute_backup_run" ;;
esac

api="https://alert.janedoe.com/api/v2"
auth="admin:$("${rendered}/base/podman/get_secret.sh" alertmanager_admin_password)"

am() { curl -fsS -m 15 -u "$auth" "$@"; }

# Fetched first: a failure inside the for list would pass unnoticed
silences=$(am "${api}/silences")
ended=0
for id in $(jq -r --arg c "$creator" \
    '.[] | select(.createdBy == $c and .status.state == "active") | .id' <<< "$silences"); do
  am -X DELETE "${api}/silence/${id}"
  ended=$((ended + 1))
done

if [[ -z $hours ]]; then
  echo "Alerts unmuted (${ended} silence(s) ended)"
  exit 0
fi

ends=$(date -u -d "+${hours} hours" +%FT%TZ)
body=$(jq -n --arg start "$(date -u +%FT%TZ)" --arg end "$ends" --arg c "$creator" \
  --arg hours "$hours" --arg what "$what" --argjson matchers "$matchers" '{
    matchers: $matchers,
    startsAt: $start, endsAt: $end, createdBy: $c,
    comment: "\($what) muted for \($hours) h by mute_alerts.sh"
  }')
id=$(am -H 'Content-Type: application/json' -d "$body" "${api}/silences" | jq -r .silenceID)
echo "Alerts muted until $(date -d "$ends" '+%a %H:%M %Z') (silence ${id})"
