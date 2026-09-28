#!/bin/bash
# Renders the source code into the given folder. Fills in personal details from vars.yml.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/render_src.sh [/dir/to/store/rendered/homelab-rendered]
# Without an argument it renders into a private temp dir and prints the path.
# Ref:
# https://manpages.debian.org/buster/fd-find/fdfind.1.en.html
# https://github.com/kpfleming/jinjanator
# Note:
# The *.j2.j2 extension indicates that the file will go thru a second pass of jinjanate,
# usually during service startup. See src/podman/render_secrets.sh for an example.

set -euo pipefail

# Prepare the output directory. The default is a mktemp (0700) parent; the name
# homelab-rendered is kept because upload_src.sh moves the tree into place by it.
project_dir=${1:-"$(mktemp -d)/homelab-rendered"}
mkdir -p "$project_dir"
# An exclude list rather than copy-then-delete, so personal details never touch the
# output, even briefly
rsync -a --delete \
  --exclude /.git --exclude /.gitignore --exclude /.vscode --exclude /.fdignore \
  --exclude /.claude --exclude /.scratch --exclude /planning --exclude /notes \
  --exclude /rendered --exclude /.gitattributes \
  --exclude vars.yml --exclude all_vars.yml --exclude .DS_Store \
  ./ "$project_dir/"

# Assemble jinja2 config file. jinjanate takes one data file, so the node inventory
# is appended to vars.yml rather than passed alongside it. It holds everything in
# vars.yml, so it lives in its own private temp dir, outside the repo and the output.
vars_dir=$(mktemp -d)
trap 'rm -rf "$vars_dir"' EXIT
all_vars="${vars_dir}/all_vars.yml"
cut_line=$(grep -n "^\.\.\." vars.yml | cut -d: -f1)
{
  # Exclude the ending "..."
  head -n "$((cut_line-1))" vars.yml
  echo
  cat src/nodes.yml
  echo -e "...\n"
} > "$all_vars"

# Render the files
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
$fdfind . --type f -e j2 --exec rm "${project_dir}/{}"
$fdfind . --type f -e j2 --exec jinjanate --quiet -o "${project_dir}/{.}" "{}" "$all_vars"

cd "$project_dir"

# Make executable
$fdfind . --extension sh --exec chmod +x "{}"
$fdfind . --extension pl --exec chmod +x "{}"

tools/validate_rendered.sh .

fail() { echo "error: $*" >&2; exit 1; }

# Validate each image in src/nodes.yml against the quadlet its install case copies. The
# image updater loads images under these names, so a mismatch would never be updated.
upstreams='.. | select(tag == "!!map" and has("upstream")) | .upstream'
bad=$(yq "$upstreams" src/nodes.yml | grep -vE '^[^/]+\.[^/]+/[^/]+/[^/]+' || true)
[ -z "$bad" ] || fail "src/nodes.yml upstream refs need a registry host and namespace: ${bad}"

cat > "${vars_dir}/images.j2" <<'EOF'
{% import 'src/nodes.jinja' as inv with context -%}
{% for node, list in inv.images.items() -%}
{% for i in list -%}
{{ node }} {{ i.service }} {{ i.container }} {{ i.image }}
{% endfor -%}
{% endfor -%}
EOF
jinjanate --quiet "${vars_dir}/images.j2" "$all_vars" | \
  while read -r node svc container image; do
    quadlet=$(awk -v c="${svc})" '$1 == c {f=1; next} f && /;;/ {exit} f' "src/${node}/install_svcs.sh" | \
      grep -oE "[a-zA-Z0-9_./-]+/${container}\.container" | head -n 1 || true)
    [ -n "$quadlet" ] || \
      fail "the ${svc} case in src/${node}/install_svcs.sh copies no ${container}.container (src/nodes.yml)"
    # A *.container.j2.j2 source is still *.container.j2 until install time
    file="src/${quadlet}"
    [ -f "$file" ] || file+=".j2"
    actual=$(sed -n 's/^Image=//p' "$file")
    [[ "$actual" == "$image" ]] || \
      fail "${file}: Image=${actual}, expected Image=${image} (src/nodes.yml ${node}.services.${svc})"
  done

# Validate the node inventory against the scripts its dispatcher cases call
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
  # shellcheck disable=SC2016 # the backticks are literal regex text
  routed=$(yq --yaml-fix-merge-anchor-to-spec=true '.http.routers[].rule' "src/${node}/traefik/routes.yml" | \
    grep -oE 'Host\(`[^.`]+\.' | sed -E 's/^Host\(`//; s/\.$//' | sort -u)
  listed=$(inventory "$node" '.nodes[strenv(node)].services[] | select(has("subdomain")) | .subdomain' | sort -u)
  [[ "$routed" == "$listed" ]] || \
    fail "src/nodes.yml ${node} subdomains don't match the Host() rules in src/${node}/traefik/routes.yml"
done

find . -name .DS_Store -delete
echo "Rendered the repo into ${project_dir}"
