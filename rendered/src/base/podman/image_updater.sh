#!/bin/bash
# Keeps this node's container images current behind a vulnerability scan. For each image
# in the node inventory's update order (src/nodes.jinja images[node]) whose quadlet is
# installed: compare the upstream digest with the one handled last, download a changed
# one, scan it with Trivy (fixable HIGH or CRITICAL blocks it), load it under its
# localhost/ name and let `podman auto-update` restart the containers on it. Quadlets
# only name localhost/ images with AutoUpdate=local, so nothing unscanned reaches a
# container. Design: docs/adr/0008-scanned-image-updater.md.
# Usage:
#   src/base/podman/image_updater.sh                  # image_updater.timer, nightly
#   src/base/podman/image_updater.sh --dry-run        # check and scan; loads and restarts nothing
#   src/base/podman/image_updater.sh install SERVICE  # install_svcs.sh, before copying quadlets
#   sudo src/base/podman/image_updater.sh accept CONTAINER  # as manualadmin, never the dispatcher
# Overrides for a blocked image, both needing a person: src/services/<service>/.trivyignore
# (`CVE-… exp:YYYY-MM-DD`, with a `#` line giving the reason) covers every digest until it
# expires; `accept` rescans, prints the findings and passes that exact digest.

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

node=$(hostname)
self="${rendered}/base/podman/image_updater.sh"
var=/var/lib/image_updater
# state/<container>: "<remote digest> <outcome>" of the digest handled last;
# state/<container>.blocked: when the scan gate first blocked it
state="${var}/state"
staging="${var}/staging"
# accepted/<container>: digests `accept` passed, one per line
accepted="${var}/accepted"
metrics=/var/lib/node_exporter/textfile_collector/image_updater.prom
trivy_cache=/var/cache/trivy

# images: "SERVICE CONTAINER IMAGE upstream REF" or "SERVICE CONTAINER IMAGE build NAME",
# in update order. deadline_s: no image is started after this many seconds, so the run
# stays inside its 30-minute slot (image_updater.timer); what's left runs the next night.
# The notification path runs on secsvcs, its slot is last, and nothing has to fit after it.
case $node in
  homesvcs)
    images=(
      "traefik traefik localhost/library/traefik:v3.7 upstream docker.io/library/traefik:v3.7"
      "vmagent vmagent localhost/victoriametrics/vmagent:latest upstream docker.io/victoriametrics/vmagent:latest"
      "mosquitto mosquitto localhost/library/eclipse-mosquitto:latest upstream docker.io/library/eclipse-mosquitto:latest"
      "zigbee2mqtt zigbee2mqtt localhost/koenkk/zigbee2mqtt:latest upstream ghcr.io/koenkk/zigbee2mqtt:latest"
      "home_assistant home_assistant localhost/homeassistant/home-assistant:2026.3.1 upstream docker.io/homeassistant/home-assistant:2026.3.1"
      "fluentbit fluentbit localhost/fluent/fluent-bit:3.2 upstream docker.io/fluent/fluent-bit:3.2"
    )
    # Container subnets are local to each node, so ntfy is reached through Traefik.
    ntfy_url="https://push.janedoe.com/alert"
    deadline_s=1500
    boot_delay_s=0
    ;;
  secsvcs)
    images=(
      "postgres postgres localhost/library/postgres:14-alpine upstream docker.io/library/postgres:14-alpine"
      "lldap lldap localhost/lldap/lldap:stable upstream docker.io/lldap/lldap:stable"
      "authelia authelia localhost/authelia/authelia:4.39 upstream docker.io/authelia/authelia:4.39"
      "victorialogs victorialogs localhost/victoriametrics/victoria-logs:latest upstream docker.io/victoriametrics/victoria-logs:latest"
      "gatus gatus localhost/twinproduction/gatus:latest upstream docker.io/twinproduction/gatus:latest"
      "grafana grafana localhost/grafana/grafana-oss:latest upstream docker.io/grafana/grafana-oss:latest"
      "olive_tin olive_tin localhost/jamesread/olivetin:latest-3k upstream docker.io/jamesread/olivetin:latest-3k"
      "crowdsec crowdsec localhost/crowdsecurity/crowdsec:latest upstream docker.io/crowdsecurity/crowdsec:latest"
      "fluentbit fluentbit localhost/fluent/fluent-bit:3.2 upstream docker.io/fluent/fluent-bit:3.2"
      "traefik traefik localhost/library/traefik:v3.7 upstream docker.io/library/traefik:v3.7"
      "victoriametrics victoriametrics localhost/victoriametrics/victoria-metrics:latest upstream docker.io/victoriametrics/victoria-metrics:latest"
      "vmalert vmalert localhost/victoriametrics/vmalert:latest upstream docker.io/victoriametrics/vmalert:latest"
      "alertmanager alertmanager localhost/prom/alertmanager:latest upstream docker.io/prom/alertmanager:latest"
      "ntfy-alertmanager ntfy-alertmanager localhost/xenrox/ntfy-alertmanager:latest upstream docker.io/xenrox/ntfy-alertmanager:latest"
      "ntfy ntfy localhost/binwiederhier/ntfy:latest upstream docker.io/binwiederhier/ntfy:latest"
    )
    # Straight to the container: no DNS, Traefik or TLS between this script and ntfy
    # while their images update. IP: ntfy.container.
    ntfy_url="http://10.10.0.13:2586/alert"
    deadline_s=0
    # A catch-up run after a pve1 reboot waits for ntfy and the rest to settle.
    boot_delay_s=900
    ;;
  vpnsvcs)
    images=(
      "fluentbit fluentbit localhost/fluent/fluent-bit:3.2 upstream docker.io/fluent/fluent-bit:3.2"
      "vmagent vmagent localhost/victoriametrics/vmagent:latest upstream docker.io/victoriametrics/vmagent:latest"
      "geoip_generator geoip_generator localhost/geoip_generator:latest build geoip_generator"
    )
    # Container subnets are local to each node, so ntfy is reached through Traefik.
    ntfy_url="https://push.janedoe.com/alert"
    deadline_s=1500
    boot_delay_s=0
    ;;
  websvcs)
    images=(
      "traefik traefik localhost/library/traefik:v3.7 upstream docker.io/library/traefik:v3.7"
      "vmagent vmagent localhost/victoriametrics/vmagent:latest upstream docker.io/victoriametrics/vmagent:latest"
      "nginx nginx localhost/library/nginx:stable upstream docker.io/library/nginx:stable"
      "homepage homepage localhost/gethomepage/homepage:latest upstream ghcr.io/gethomepage/homepage:latest"
      "isso isso localhost/isso-comments/isso:release upstream ghcr.io/isso-comments/isso:release"
      "guacamole guacamole localhost/guacamole/guacamole:1.6.0 upstream docker.io/guacamole/guacamole:1.6.0"
      "guacd guacd localhost/guacamole/guacd:1.6.0 upstream docker.io/guacamole/guacd:1.6.0"
      "linkding linkding localhost/sissbruecker/linkding:latest-plus upstream docker.io/sissbruecker/linkding:latest-plus"
      "readeck readeck localhost/readeck/readeck:latest upstream codeberg.org/readeck/readeck:latest"
      "fluentbit fluentbit localhost/fluent/fluent-bit:3.2 upstream docker.io/fluent/fluent-bit:3.2"
      "storyteller storyteller localhost/storyteller-platform/storyteller:web-v2 upstream registry.gitlab.com/storyteller-platform/storyteller:web-v2"
      "calliope calliope localhost/calliope:latest build calliope"
    )
    # Container subnets are local to each node, so ntfy is reached through Traefik.
    ntfy_url="https://push.janedoe.com/alert"
    deadline_s=1500
    boot_delay_s=0
    ;;
  *)
    die "no image list for ${node}"
    ;;
esac

secret() {
  local value
  value=$("${rendered}/base/podman/get_secret.sh" "$1")
  [[ $value == null ]] || echo "$value"
}

# Usage: notify PRIORITY TITLE MESSAGE. ntfy may still be starting after a pve1 reboot.
notify() {
  curl -fsS -o /dev/null -m 15 --retry 8 --retry-delay 30 --retry-all-errors \
    -H "Authorization: Bearer $(secret ntfy_alert_token)" \
    -H "X-Title: ${node}: $2" \
    -H "X-Priority: $1" \
    -H "X-Tags: package" \
    -d "$3" "$ntfy_url" ||
    warn "ntfy post failed: $2"
}

# Docker Hub's anonymous pull limit is per IP, shared by every VM behind the router.
auth=()
registry_auth() {
  local user token
  user=$(secret docker_hub_username)
  token=$(secret docker_hub_token)
  if [[ -z $user || -z $token ]]; then
    warn "no Docker Hub credentials in the secrets file; pulling anonymously"
    return
  fi
  ( umask 077
    jq -n --arg auth "$(printf '%s:%s' "$user" "$token" | base64 -w0)" \
      '{auths: {"docker.io": {auth: $auth}}}' > "${tmp}/auth.json" )
  auth=(--authfile "${tmp}/auth.json")
}

# A scan never runs against a stale database: the caller fails when this does.
trivy_refresh() {
  trivy image --quiet --cache-dir "$trivy_cache" --download-db-only &&
    trivy image --quiet --cache-dir "$trivy_cache" --download-java-db-only
}

# Usage: scan SERVICE INPUT REPORT; exit 0 passes, 3 has findings, anything else is an error
scan() {
  local ignore=()
  if [[ -f ${rendered}/services/$1/.trivyignore ]]; then
    ignore=(--ignorefile "${rendered}/services/$1/.trivyignore")
  fi
  trivy image --quiet --cache-dir "$trivy_cache" --cache-backend memory \
    --skip-db-update --skip-java-db-update --scanners vuln \
    --severity HIGH,CRITICAL --ignore-unfixed --exit-code 3 \
    --format json --output "$3" "${ignore[@]}" --input "$2"
}

# Usage: findings REPORT; one line per finding
findings() {
  jq -r '.Results[]? | .Target as $t | .Vulnerabilities[]? |
    "\(.Severity) \(.VulnerabilityID) \(.PkgName) \(.InstalledVersion) -> \(.FixedVersion) (\($t))"' "$1"
}

last_digest() { cut -d' ' -f1 "${state}/$1" 2> /dev/null || true; }

# Usage: record CONTAINER DIGEST OUTCOME; the digest isn't handled again until upstream moves
record() {
  echo "$2 $3" > "${state}/$1"
  rm -f "${state}/$1.blocked"
}

# Usage: result OUTCOME [MESSAGE]; ends an attempt subshell with its outcome
result() {
  [[ -z ${2:-} ]] || log "${container}: $2"
  echo "$1" > "${tmp}/result"
  exit 0
}

# Usage: attempt FUNCTION ARGS...; sets outcome to the result FUNCTION ended with, or
# broken if it failed. The subshell turns errexit back on, which bash ignores inside
# anything called from a condition, and keeps one image's failure from ending the run.
attempt() {
  local rc
  : > "${tmp}/result"
  set +e
  ( set -e; "$@" )
  rc=$?
  set -e
  outcome=broken
  if (( rc == 0 )) && [[ -s ${tmp}/result ]]; then
    outcome=$(cat "${tmp}/result")
  fi
}

# Usage: blocked CONTAINER DIGEST REPORT; the scan gate stopped DIGEST, the old image
# keeps running
blocked() {
  local since days ids
  findings "$3"
  case $mode in
    run)
      [[ -f ${state}/$1.blocked ]] || date +%s > "${state}/$1.blocked"
      since=$(cat "${state}/$1.blocked")
      days=$(( ($(date +%s) - since) / 86400 ))
      ids=$(jq -r '[.Results[]?.Vulnerabilities[]?.VulnerabilityID] | unique |
        (.[0:10] | join(", ")) + (if length > 10 then ", …" else "" end)' "$3")
      if (( days < 7 )); then
        notify 3 "$1 update blocked" "$2 has fixable HIGH/CRITICAL CVEs: ${ids}. The old image keeps running."
      else
        notify 5 "$1 blocked for ${days} days" "$2 has fixable HIGH/CRITICAL CVEs: ${ids}. To override after review, add them to src/services/<service>/.trivyignore with an exp: date, or ssh manualadmin@${node} and run: sudo ${self} accept $1"
      fi
      ;;
    install)
      log "after review, to override: sudo ${self} accept $1 (as manualadmin), then install again"
      ;;
  esac
}

# Usage: gate SERVICE CONTAINER KEY INPUT; returns if the image at INPUT passes the scan,
# else ends the attempt as blocked. KEY is the digest or versions `accept` would record.
gate() {
  local report="${tmp}/$2.json" rc=0
  if grep -qxF "$3" "${accepted}/$2" 2> /dev/null; then
    log "$2: $3 was accepted; not gated"
    return
  fi
  scan "$1" "$4" "$report" || rc=$?
  case $rc in
    0) log "$2: scan passed" ;;
    3) blocked "$2" "$3" "$report"; result blocked "blocked by the scan" ;;
    *) die "trivy failed on $2 (exit ${rc})" ;;
  esac
}

# Usage: keep_rollback IMAGE; what IMAGE names now stays reachable as its :rollback
keep_rollback() {
  if podman image exists "$1"; then
    podman tag "$1" "${1%:*}:rollback"
  fi
}

# Usage: roll_out CONTAINER IMAGE KEY; IMAGE names the new image now. Restarts the
# container on it, or puts the :rollback image back.
roll_out() {
  local container=$1 image=$2 key=$3 out updated
  if [[ $mode == install ]]; then
    record "$container" "$key" loaded
    result loaded "loaded ${key}"
  fi
  # Exit codes aren't documented, so only the report counts. Each call also acts on
  # every other AutoUpdate=local container, which is why a failed image is pointed back
  # at :rollback below before the next one.
  out=$(podman auto-update --format json) || true
  updated=$(jq -r --arg unit "${container}.service" '.[]? | select(.Unit == $unit) | .Updated' <<< "$out")
  case $updated in
    true)
      record "$container" "$key" updated
      result updated "updated to ${key}"
      ;;
    false)
      record "$container" "$key" current
      result current "already running ${key}"
      ;;
    "")
      # Not running, or its quadlet doesn't use AutoUpdate=local
      record "$container" "$key" loaded
      result loaded "loaded ${key}; no running container uses it"
      ;;
    *)
      if podman image exists "${image%:*}:rollback"; then
        podman tag "${image%:*}:rollback" "$image"
      fi
      systemctl is-active --quiet "${container}.service" || systemctl restart "${container}.service" || true
      record "$container" "$key" failed
      notify 4 "${container} update failed" "${key} didn't start (auto-update: ${updated}); back on the previous image. Not retried until upstream changes."
      result failed "update failed (${updated}); rolled back"
      ;;
  esac
}

# Usage: check_upstream SERVICE CONTAINER IMAGE UPSTREAM; one pulled image, ending with
# result unchanged, pass (dry run), loaded, current, updated, failed, blocked or error
check_upstream() {
  local service=$1 container=$2 image=$3 upstream=$4 dir="${staging}/$2" digest
  # Always remote against remote: a multi-arch tag's digest isn't the local image's.
  digest=$(skopeo inspect --no-tags "${auth[@]}" "docker://${upstream}" | jq -r .Digest) ||
    result error "can't inspect ${upstream}; trying again tomorrow"
  if [[ $(last_digest "$container") == "$digest" ]] && podman image exists "$image"; then
    result unchanged "unchanged at ${digest}"
  fi
  log "${container}: ${upstream} is at ${digest}"
  rm -rf "$dir"
  # By digest, so what's scanned is what the inspect saw even if the tag moves meanwhile
  skopeo copy --quiet "${auth[@]}" "docker://${upstream%:*}@${digest}" "oci:${dir}" ||
    result error "can't download ${upstream}; trying again tomorrow"
  gate "$service" "$container" "$digest" "$dir"
  [[ $mode != dry-run ]] || result pass "would load ${digest} as ${image}"
  keep_rollback "$image"
  skopeo copy --quiet "oci:${dir}" "containers-storage:${image}"
  roll_out "$container" "$image" "$digest"
}

# Usage: check_build SERVICE CONTAINER IMAGE NAME; one image built here, ending like
# check_upstream. src/services/SERVICE/build.sh takes `versions` (print the upstream release
# versions it builds from) and `build TAG` (build localhost/NAME:TAG from them); an image
# without one, or without releases to follow, is only built by hand.
check_build() {
  local service=$1 container=$2 image=$3 name=$4 script="${rendered}/services/$1/build.sh"
  local candidate="localhost/$4:candidate" archive="${staging}/$2.tar" versions id
  [[ -x $script ]] || result unchanged "built by hand"
  versions=$("$script" versions | tr -s ' \n' ',') ||
    result error "can't resolve ${name}'s release versions; trying again tomorrow"
  versions=${versions%,}
  if [[ $(last_digest "$container") == "$versions" ]] && podman image exists "$image"; then
    result unchanged "unchanged at ${versions}"
  fi
  log "${container}: building ${versions}"
  "$script" build candidate
  # Scanned from a file, so Trivy doesn't need the podman socket. Untagged before the
  # gate, so a blocked build is only a dangling image the next prune removes.
  podman save -o "$archive" "$candidate"
  id=$(podman image inspect "$candidate" | jq -r '.[0].Id')
  podman untag "$candidate"
  gate "$service" "$container" "$versions" "$archive"
  [[ $mode != dry-run ]] || result pass "would tag ${versions} as ${image}"
  keep_rollback "$image"
  podman tag "$id" "$image"
  roll_out "$container" "$image" "$versions"
}

# Every run waits for boot, inside the script: a timer firing during boot would
# otherwise hold boot open while its unit waits on it.
wait_for_boot() {
  local status up
  status=$(systemctl is-system-running --wait) || true
  case $status in
    running) ;;
    degraded)
      warn "system degraded, failed units: $(systemctl list-units --failed --plain --no-legend | awk '{print $1}' | xargs)"
      ;;
    *) die "system is ${status}" ;;
  esac
  up=$(cut -d. -f1 /proc/uptime)
  if (( up < boot_delay_s )); then
    log "waiting $(( boot_delay_s - up ))s after boot"
    sleep $(( boot_delay_s - up ))
  fi
}

declare -A count=([checked]=0 [updated]=0 [blocked]=0 [failed]=0 [error]=0 [broken]=0 [deferred]=0)

# Keeps the previous success timestamp when this run failed, so the age alert counts
# from the last good run.
write_metrics() {
  local ok=$1 name=image_updater_last_success_timestamp_seconds last f since result
  last=$(awk -v n="$name" '$1 == n { print $2 }' "$metrics" 2> /dev/null || true)
  (( ! ok )) || last=$(date +%s)
  mkdir -p "$(dirname "$metrics")"
  {
    echo "# HELP ${name} Unix time of the last image_updater run with no broken image."
    echo "# TYPE ${name} gauge"
    [[ -z $last ]] || echo "${name} ${last}"
    echo "# HELP image_updater_images Images in the last image_updater run, by result."
    echo "# TYPE image_updater_images gauge"
    for result in "${!count[@]}"; do
      echo "image_updater_images{result=\"${result}\"} ${count[$result]}"
    done
    echo "# HELP image_updater_blocked_days Days since the scan gate first blocked the container's update."
    echo "# TYPE image_updater_blocked_days gauge"
    for f in "${state}"/*.blocked; do
      [[ -e $f ]] || continue
      since=$(cat "$f")
      echo "image_updater_blocked_days{container=\"$(basename "$f" .blocked)\"} $(( ($(date +%s) - since) / 86400 ))"
    done
  } > "${metrics}.tmp"
  chmod 644 "${metrics}.tmp"
  # node_exporter only reads *.prom, and the rename is atomic.
  mv "${metrics}.tmp" "$metrics"
}

# Usage: finish OK; the end of a nightly run, whatever happened
finish() {
  write_metrics "$1" || warn "writing metrics failed"
  exit $(( ! $1 ))
}

update_all() {
  local service container image kind ref entry started=$SECONDS broken=()
  (( mode_dry )) || wait_for_boot
  registry_auth
  if ! trivy_refresh; then
    (( mode_dry )) && die "Trivy DB refresh failed"
    warn "Trivy DB refresh failed; nothing checked"
    notify 5 "Image updater broken" "Trivy DB refresh failed, so nothing was checked."
    finish 0
  fi
  for entry in "${images[@]}"; do
    read -r service container image kind ref <<< "$entry"
    [[ -f /etc/containers/systemd/${container}.container ]] || continue
    if (( ! mode_dry && deadline_s && SECONDS - started > deadline_s )); then
      log "${container}: past the deadline, left for tomorrow"
      (( ++count[deferred] ))
      continue
    fi
    (( ++count[checked] ))
    attempt "check_${kind}" "$service" "$container" "$image" "$ref"
    case $outcome in
      updated | blocked | failed | error) (( ++count[$outcome] )) ;;
      broken)
        (( ++count[broken] ))
        broken+=("$container")
        warn "${container}: pipeline broken"
        ;;
    esac
  done
  if (( mode_dry )); then
    [[ -z ${broken[*]} ]] || die "broken: ${broken[*]}"
    return
  fi
  podman image prune -f > /dev/null || warn "image prune failed"
  if [[ -n ${broken[*]} ]]; then
    notify 5 "Image updater broken" "Failed on: ${broken[*]}. See journalctl -u image_updater."
    finish 0
  fi
  finish 1
}

# Usage: install_images SERVICE; every image of SERVICE is loaded and passed the scan
# gate before its quadlet is copied, or the install stops here.
install_images() {
  local service container image kind ref entry ready=0
  for entry in "${images[@]}"; do
    read -r service container image kind ref <<< "$entry"
    [[ $service == "$1" ]] || continue
    if (( ! ready )); then
      registry_auth
      trivy_refresh || die "Trivy DB refresh failed"
      ready=1
    fi
    attempt "check_${kind}" "$service" "$container" "$image" "$ref"
    case $outcome in
      unchanged | loaded) ;;
      blocked) die "${container}: blocked by the scan gate" ;;
      *) die "${container}: ${outcome}" ;;
    esac
  done
}

# Usage: accept CONTAINER; passes the current upstream digest through the scan gate
accept() {
  local service container image kind ref entry found="" digest dir report rc=0
  [[ ${SUDO_USER:-} == manualadmin ]] || die "accept is for manualadmin, through sudo"
  for entry in "${images[@]}"; do
    read -r service container image kind ref <<< "$entry"
    if [[ $container == "$1" ]]; then
      found=1
      break
    fi
  done
  [[ -n $found ]] || die "no image for container $1 on ${node}"
  [[ $kind == upstream ]] || die "$1 is built here; accept takes pulled images"
  registry_auth
  trivy_refresh || die "Trivy DB refresh failed"
  digest=$(skopeo inspect --no-tags "${auth[@]}" "docker://${ref}" | jq -r .Digest)
  dir="${staging}/${container}"
  report="${tmp}/${container}.json"
  rm -rf "$dir"
  skopeo copy --quiet "${auth[@]}" "docker://${ref%:*}@${digest}" "oci:${dir}"
  scan "$service" "$dir" "$report" || rc=$?
  case $rc in
    0) log "${container}: ${digest} has no fixable HIGH/CRITICAL findings" ;;
    3) findings "$report" ;;
    *) die "trivy failed (exit ${rc})" ;;
  esac
  echo "$digest" >> "${accepted}/${container}"
  log "${container}: accepted ${digest}; the next run loads it"
  notify 3 "${container} accepted" "manualadmin accepted ${digest} past the scan gate."
}

require_root
install -d -m 700 "$var" "$state" "$staging" "$accepted"
exec {lock}> /run/image_updater.lock
flock -n "$lock" || die "another image_updater is running"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp" "${staging:?}"/*' EXIT

mode_dry=0
case ${1:-} in
  "")
    mode=run
    update_all
    ;;
  --dry-run)
    mode=dry-run
    mode_dry=1
    update_all
    ;;
  install)
    mode=install
    install_images "${2:?usage: $0 install SERVICE}"
    ;;
  accept)
    mode=accept
    accept "${2:?usage: $0 accept CONTAINER}"
    ;;
  *)
    die "usage: $0 [--dry-run | install SERVICE | accept CONTAINER]"
    ;;
esac
