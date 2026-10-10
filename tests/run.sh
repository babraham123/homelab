#!/bin/bash
# Runs the test suite: every test_* function in tests/*_test.sh, each in a fresh
# subshell from the repo root under `set -euo pipefail`, all in parallel.
# Usage:
#   tests/run.sh [--fast]
# --fast skips tests/render_test.sh, the full render of vars.template.yml, which the
# pre-commit hook does anyway.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT

names=()
for file in tests/*_test.sh; do
  [[ "${1:-}" == --fast && "$file" == tests/render_test.sh ]] && continue
  for name in $(sed -nE 's/^(test_[a-z0-9_]+)\(\).*/\1/p' "$file"); do
    names+=("${file#tests/} ${name}")
    log="${logs}/${#names[@]}"
    {
      (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$file"
        "$name"
      ) > "$log" 2>&1 < /dev/null
      echo $? > "${log}.status"
    } &
  done
done
wait

failed=0
for i in "${!names[@]}"; do
  log="${logs}/$((i + 1))"
  if [ "$(cat "${log}.status")" -eq 0 ]; then
    echo "ok    ${names[i]}"
  else
    failed=$((failed + 1))
    echo "FAIL  ${names[i]}"
    sed 's/^/      /' "$log"
  fi
done
echo "${#names[@]} tests, ${failed} failed"
[ "$failed" -eq 0 ]
