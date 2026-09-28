#!/bin/bash
# Validates a rendered copy of the repo. Called by render_src.sh and, through it, by the
# pre-commit hook.
# Usage:
#   tools/validate_rendered.sh /dir/with/rendered/copy

set -euo pipefail

cd "$1"
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
fail() { echo "error: $*" >&2; exit 1; }

yamllint -c lint.yaml . || fail "yaml linting failed"

while read -r json; do
  jq -e . "$json" > /dev/null || fail "json validation failed: ${json}"
done < <($fdfind . --extension json)

dups=$($fdfind . --extension container --exec-batch grep -h "^IP=" | sort | uniq -d)
[ -z "$dups" ] || fail "duplicate IPs found: ${dups}"

# The config is kept in step with the upstream template of the image's minor version, see
# docs/maintenance.md. Patch releases don't change the template.
config_version=$(sed -nE 's/^# v([0-9]+\.[0-9]+)\..*/\1/p' src/authelia/configuration.yml)
image_version=$(sed -nE 's|^Image=.*/authelia:([0-9]+\.[0-9]+).*|\1|p' src/authelia/authelia.container)
[[ -n "$config_version" && "$config_version" == "$image_version" ]] || \
  fail "src/authelia/configuration.yml is for Authelia ${config_version:-?} but the image is ${image_version:-?}"
