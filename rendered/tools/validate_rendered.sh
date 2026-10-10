#!/bin/bash
# Validates a rendered copy of the repo. Called by render_src.sh and, through it, by the
# pre-commit hook.
# Usage:
#   tools/validate_rendered.sh /dir/with/rendered/copy

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$1"
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
yamllint -c lint.yaml . || die "yaml linting failed"

while read -r json; do
  jq -e . "$json" > /dev/null || die "json validation failed: ${json}"
done < <($fdfind . --extension json)

dups=$($fdfind . --extension container --exec-batch grep -h "^IP=" | sort | uniq -d)
[ -z "$dups" ] || die "duplicate IPs found: ${dups}"
