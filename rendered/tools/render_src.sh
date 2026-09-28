#!/bin/bash
# Renders the source code into the given folder. Fills in personal details from vars.yml.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/render_src.sh /dir/to/store/rendered/copy
# Ref:
# https://manpages.debian.org/buster/fd-find/fdfind.1.en.html
# https://github.com/kpfleming/jinjanator
# Note:
# The *.j2.j2 extension indicates that the file will go thru a second pass of jinjanate,
# usually during service startup. See src/podman/render_secrets.sh for an example.

set -euo pipefail

# Prepare the output directory
project_dir=$1
rm -rf "$project_dir" all_vars.yml
mkdir -p "$project_dir"
cp -R . "$project_dir"
pushd "$project_dir"
rm -rf .git .gitignore .gitattributes vars.yml .vscode .fdignore notes planning rendered
popd

# Assemble jinja2 config file. jinjanate takes one data file, so the node inventory
# is appended to vars.yml rather than passed alongside it.
cut_line=$(grep -n "^\.\.\." vars.yml | cut -d: -f1)
{
  # Exclude the ending "..."
  head -n "$((cut_line-1))" vars.yml
  echo
  cat src/nodes.yml
  echo -e "...\n"
} > all_vars.yml

# Render the files
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
$fdfind . --type f -e j2 --exec rm "${project_dir}/{}"
$fdfind . --type f -e j2 --exec jinjanate --quiet -o "${project_dir}/{.}" "{}" all_vars.yml

rm -f all_vars.yml
cd "$project_dir"

# Make executable
$fdfind . --extension sh --exec chmod +x "{}"
$fdfind . --extension pl --exec chmod +x "{}"

tools/validate_rendered.sh .

# Validate the node inventory against the scripts its dispatcher cases call
fail() { echo "error: $*" >&2; exit 1; }
cases() { sed -nE 's/^[[:space:]]+([a-zA-Z0-9_-]+)\).*$/\1/p' "$1" | sort -u; }
inventory() { node="$1" yq "$2" src/nodes.yml; }

for node in $(yq '.nodes | keys | .[]' src/nodes.yml); do
  install_file="src/${node}/install_svcs.sh"
  actual=""
  [ -f "$install_file" ] && actual=$(cases "$install_file")
  listed=$(inventory "$node" '.nodes[strenv(node)].services // {} | keys | .[]' | sort -u)
  [[ "$listed" == "$actual" ]] || \
    fail "src/nodes.yml ${node}.services doesn't match the cases in ${install_file}"

  for svc in $(inventory "$node" '.nodes[strenv(node)].debian_services // [] | .[]'); do
    cases src/debian/install_svcs.sh | grep -qx "$svc" || \
      fail "src/debian/install_svcs.sh has no ${svc} case (src/nodes.yml ${node}.debian_services)"
  done

  inventory "$node" '.nodes[strenv(node)].commands // [] | .[] | select(has("script")) | .name + " " + .script' | \
    while read -r name script; do
      [ -f "src/${script}" ] || fail "src/${script} doesn't exist (src/nodes.yml ${node}.commands)"
      cases "src/${script}" | grep -qx "$name" || fail "src/${script} has no ${name} case"
    done
done

subdomains='.nodes[] | select(has("services")) | .services[] | select(has("subdomain")) | .subdomain'
dups=$(yq "$subdomains" src/nodes.yml | sort | uniq -d)
[ -z "$dups" ] || fail "subdomains listed more than once in src/nodes.yml: ${dups}"

# The subdomain lists drive DNS and SNI routing, so they must match what Traefik serves.
# websvcs is the default route and needs no entries.
for node in secsvcs homesvcs; do
  routed=$(yq --yaml-fix-merge-anchor-to-spec=true '.http.routers[].rule' "src/${node}/traefik/routes.yml" | \
    grep -oE 'Host\(`[^.`]+\.' | sed -E 's/^Host\(`//; s/\.$//' | sort -u)
  listed=$(inventory "$node" '.nodes[strenv(node)].services[] | select(has("subdomain")) | .subdomain' | sort -u)
  [[ "$routed" == "$listed" ]] || \
    fail "src/nodes.yml ${node} subdomains don't match the Host() rules in src/${node}/traefik/routes.yml"
done

rm -f "${project_dir}"/**/.DS_Store
echo "Rendered the repo into ${project_dir}"
