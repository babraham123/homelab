# shellcheck shell=bash
# Sourced first by every tools/*.sh. The workstation counterpart of src/base/lib.sh,
# which assumes a node.
#   # shellcheck source=tools/lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

warn() { echo "warning: $*" >&2; }
die()  { echo "error: $*" >&2; exit 1; }

# Prints the template data: the YAML vars on stdin, then the node inventory under DIR
# (DIR/<node>/inventory.yml) as one mapping under `nodes:`, in node-name order, then the
# lists tools/inventory.py derives from both as `inv:`. jinjanate takes one data file, so
# the render and the tests both build it here. Usage: template_vars src/nodes < vars.yml
template_vars() {
  local vars inv inventory
  vars=$(
    cat
    echo
    echo "nodes:"
    for inventory in "$1"/*/inventory.yml; do
      echo "  $(basename "$(dirname "$inventory")"):"
      sed 's/^/    /' "$inventory"
    done
  )
  inv=$(printf '%s\n' "$vars" | "$(dirname "${BASH_SOURCE[0]}")/inventory.py" derive) || return
  printf '%s\ninv: %s\n' "$vars" "$inv"
}

# The pre-commit checks, run from the root of a disposable copy of the repo (the
# pre-commit hook's export of the index, tools/check.sh's copy of the working tree):
# renders it with vars.template.yml into $1, which runs every render-time check (see
# tools/check_rendered.py), lints planning/'s markdown, runs the fixture tests in tests/,
# then shellchecks the rendered scripts and ruff-checks the rendered Python, so *.j2
# files are checked with their Jinja filled in. Prints what failed; returns 1 if
# anything did.
run_checks() {
  local out=$1 logs tool status=0
  for tool in jinjanate uv fd yq yamllint jq shellcheck markdownlint-cli2; do
    command -v "$tool" > /dev/null || { echo "${tool} not installed" >&2; return 1; }
  done
  logs=$(mktemp -d)

  VARS_FILE=vars.template.yml tools/render_src.sh "$out" > "${logs}/render.log" 2>&1 || {
    status=1
    cat "${logs}/render.log" >&2
  }

  # planning/ is never rendered, so its markdown is linted here rather than by the render.
  markdownlint-cli2 "planning/**/*.md" > /dev/null || status=1

  # The render is the passing case against the real tree, so only the fixture tests run
  # here. tests/ isn't rendered, so its scripts are shellchecked in place.
  tests/run.sh --fast > "${logs}/tests.log" 2>&1 || {
    status=1
    cat "${logs}/tests.log" >&2
  }
  shellcheck -x --severity=warning tests/*.sh || status=1
  rm -rf "$logs"

  # A failed render may stop before every file is rendered; check what exists.
  (
    if [ -d "$out" ]; then cd "$out" || exit 1; fi
    status=0
    fd . --type f --extension sh --exec-batch \
      shellcheck -x --source-path=SCRIPTDIR --severity=warning .githooks/pre-commit || status=1
    # Syntax errors, undefined names, unused imports and variables
    fd . --type f --extension py --exec-batch \
      uvx --quiet ruff@0.17.2 check --quiet --no-cache --select E9,F || status=1
    exit "$status"
  ) || status=1
  return "$status"
}
