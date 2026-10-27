#!/bin/bash
# Runs the pre-commit hook's checks (tools/lib.sh run_checks) against the working tree,
# uncommitted and untracked changes included, without touching the index or rendered/.
# Works on a temp copy of the tracked and untracked, not ignored, files, plus vars.yml if
# present, so the tests that read it see the real one; the render still uses
# vars.template.yml, as the hook's does.
# Usage:
#   tools/check.sh

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --cached still lists tracked files deleted from the working tree; skip those.
git ls-files -z --cached --others --exclude-standard |
  while IFS= read -r -d '' file; do
    if [ -e "$file" ] || [ -L "$file" ]; then printf '%s\0' "$file"; fi
  done |
  rsync -a --from0 --files-from=- ./ "${tmp}/src/"
if [ -f vars.yml ]; then cp -p vars.yml "${tmp}/src/"; fi

cd "${tmp}/src"
if run_checks "${tmp}/rendered"; then
  echo "check: passed"
else
  echo "check: failed (paths are relative to the repo root)" >&2
  exit 1
fi
