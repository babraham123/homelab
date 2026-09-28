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
