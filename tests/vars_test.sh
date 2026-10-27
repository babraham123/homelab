# shellcheck shell=bash
# vars.template.yml documents every key vars.yml must have, and render_src.sh says why it
# can't use a vars file rather than failing silently.
# shellcheck source=tests/lib.sh
source tests/lib.sh

# Sorted top-level keys, or a failure if the file isn't one valid YAML document
top_keys() {
  yq -e 'keys | sort | .[]' "$1" || flunk "$1 does not parse as YAML"
}

# vars.yml is gitignored, so only the main checkout has it to compare
test_vars_files_have_the_same_keys() {
  template=$(top_keys vars.template.yml)
  [ -n "$template" ] || flunk "vars.template.yml has no keys"
  if [ -f vars.yml ]; then
    assert_eq "$(top_keys vars.yml)" <<< "$template"
  fi
}

test_render_rejects_vars_without_end_marker() {
  sed '/^\.\.\./d' vars.template.yml > "${tmp}/vars.yml"
  if out=$(VARS_FILE="${tmp}/vars.yml" tools/render_src.sh "${tmp}/homelab-rendered" 2>&1); then
    flunk "render passed without the closing '...'"
  fi
  assert_eq "$out" <<EOF
error: ${tmp}/vars.yml has no closing '...' line: end it with a line of just '...', like vars.template.yml
EOF
}

test_render_rejects_missing_vars() {
  if out=$(VARS_FILE="${tmp}/vars.yml" tools/render_src.sh "${tmp}/homelab-rendered" 2>&1); then
    flunk "render passed without a vars file"
  fi
  assert_eq "$out" <<EOF
error: ${tmp}/vars.yml not found: copy vars.template.yml to vars.yml and fill in the real values
EOF
}
