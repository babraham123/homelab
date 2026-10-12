# shellcheck shell=bash
# Shared by the timer-driven scripts that move bookmarks between services on websvcs
# (linkding_handoff.sh, readeck_narrate.sh). They reach each app on its container IP,
# not through Traefik, so Authelia isn't in the path; the app's own token is.
# Usage, from a script running as root, after src/base/lib.sh:
#   # shellcheck source=src/services/readeck/handoff_lib.sh
#   source "${rendered}/services/readeck/handoff_lib.sh"
#   token=$(secret NAME)          # a value from /etc/opt/secrets (ADR 0004)
#   api METHOD URL AUTH [CURL_ARG...]
#                                 # prints the response body; fails on a non-2xx
#                                 # status. AUTH is the full Authorization value.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

secret() {
  local value
  # shellcheck disable=SC2154 # rendered is set by src/base/lib.sh, sourced first
  value=$("${rendered}/base/podman/get_secret.sh" "$1")
  [[ -n $value && $value != null ]] || die "secret $1 is empty"
  echo "$value"
}

api() {
  local method=$1 url=$2 auth=$3
  shift 3
  curl -fsS --max-time 60 -X "$method" -H "Authorization: ${auth}" "$@" "$url"
}
