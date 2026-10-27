# shellcheck shell=bash
# Helpers shared by tests/*_test.sh. tests/run.sh sources the test file, and so this,
# in a fresh subshell per test, from the repo root.

# For template_vars, the same template data render_src.sh builds
# shellcheck source=tools/lib.sh
source tools/lib.sh

# A private scratch dir per test
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Fails the current test
flunk() {
  echo "$*" >&2
  exit 1
}

# Fails unless $1 equals stdin, showing the difference
assert_eq() {
  local expected
  expected=$(cat)
  [ "$1" == "$expected" ] || \
    flunk "$(diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$1") | sed '1s/.*/--- expected/; 2s/.*/+++ actual/')"
}

# Copies tests/fixtures/tree to $tmp/tree with the repo's lint configs, so the checks run
# with the lint rules a real render uses.
fixture_tree() {
  cp -R tests/fixtures/tree "${tmp}/tree"
  cp lint.yaml .markdownlint-cli2.yaml "${tmp}/tree/"
}

# Edits a fixture tree file in place with a sed -E script
edit() {
  local file="${tmp}/tree/$1"
  sed -E "$2" "$file" > "${file}.new"
  cmp -s "$file" "${file}.new" && flunk "edit left $1 unchanged: $2"
  mv "${file}.new" "$file"
}

# Runs tools/check_rendered.py on the fixture tree, rendered with tests/fixtures/site.yml
# and the tree's own inventory files
check_tree() {
  template_vars "${tmp}/tree/src/nodes" < tests/fixtures/site.yml > "${tmp}/all_vars.yml"
  tools/check_rendered.py "${tmp}/tree" "${tmp}/all_vars.yml" < /dev/null 2>&1
}

# Asserts check_tree fails with exactly the errors on stdin
expect_errors() {
  local out
  if out=$(check_tree); then flunk "check passed, expected it to fail with: ${out}"; fi
  assert_eq "$out"
}

# Renders the template on stdin against the inventory under $1 (<node>/inventory.yml)
render_inventory() {
  mkdir -p "${tmp}/jinja"
  template_vars "$1" < tests/fixtures/site.yml > "${tmp}/jinja/all_vars.yml"
  cat > "${tmp}/jinja/test.j2"
  (cd "${tmp}/jinja" && jinjanate --quiet test.j2 all_vars.yml)
}
