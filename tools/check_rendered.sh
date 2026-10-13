#!/bin/bash
# Checks a rendered copy of the repo: YAML, JSON, markdown and container IPs, then the node
# inventory (src/nodes/<node>/inventory.yml, ADR 0006) against the scripts, routes,
# quadlets and OliveTin buttons it describes. Called by render_src.sh; tests/ runs it
# against fixture trees.
# Usage:
#   tools/check_rendered.sh /dir/with/rendered/copy /path/to/all_vars.yml
# all_vars.yml is the data file the copy was rendered with: vars.yml plus `nodes:`.
# Reports every failure as "error: FILE: MESSAGE" and exits 1 if there was any.

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

all_vars=$2
[[ "$all_vars" == /* ]] || all_vars="${PWD}/${all_vars}"
tools=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$1"

# Traefik's fallback route: it serves hosts that have no DNS or SNI entry, so it may
# route more hosts than the inventory lists.
default_route_node=websvcs

status=0
fail() { echo "error: $1: $2" >&2; status=1; }
inventory() { echo "src/nodes/$1/inventory.yml"; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Every inventory fact the checks use, derived once by src/nodes.jinja (the same
# derivation the dispatchers, sudoers and OliveTin use), as "KIND FIELD...":
#   node NODE
#   service NODE SVC                        services, install order
#   case NODE NAME                          dispatcher cases
#   button NODE NAME                        cases OliveTin gets a button for
#   pve1_file_transfer NODE NAME            cases only pve1's certificate may run
#   run NODE LINE...                        a line a dispatcher case runs
#   subdomain NODE SUBDOMAIN
#   image NODE SVC CONTAINER IMAGE UPSTREAM upstream is - for built images
cat > "${work}/facts.j2" <<'EOF'
{% import 'src/nodes.jinja' as inv with context -%}
{% for node, spec in nodes.items() -%}
node {{ node }}
{% for svc in spec.get('services', {}) -%}
service {{ node }} {{ svc }}
{% endfor -%}
{% for entry in inv.dispatch[node] -%}
case {{ node }} {{ entry.name }}
{% if entry.pve1_file_transfer -%}
pve1_file_transfer {{ node }} {{ entry.name }}
{% else -%}
button {{ node }} {{ entry.name }}
{% endif -%}
{% for line in entry.run -%}
run {{ node }} {{ line }}
{% endfor -%}
{% endfor -%}
{% for subdomain in inv.subdomains[node] -%}
subdomain {{ node }} {{ subdomain }}
{% endfor -%}
{% for i in inv.images[node] -%}
image {{ node }} {{ i.service }} {{ i.container }} {{ i.image }} {{ i.get('upstream', '-') }}
{% endfor -%}
{% endfor -%}
EOF
jinjanate --quiet -o "${work}/facts" "${work}/facts.j2" "$all_vars" || \
  die "src/nodes.jinja: can't derive the inventory facts (jinjanate error above)"
facts() { sed -n "s/^$1 //p" "${work}/facts"; }
# Prints its argument as lines, or nothing if it is empty, so comm and `while read`
# never see a blank line
lines() { [ -z "$1" ] || printf '%s\n' "$1"; }

# Case labels of a script's `case` blocks
cases() { sed -nE 's/^[[:space:]]+([a-zA-Z0-9_-]+)\).*$/\1/p' "$1" | sort -u; }

check_yaml() {
  local out line
  out=$(yamllint -f parsable -c lint.yaml . 2>&1 | sed 's|^\./||' || true)
  while read -r line; do
    case $line in
      *" [error] "*) fail "${line%%: *}" "${line#*': [error] '}" ;;
      *" [warning] "*) warn "${line%%: *}: ${line#*': [warning] '}" ;;
      *) fail lint.yaml "yamllint: ${line}" ;;
    esac
  done < <(lines "$out")
}

check_json() {
  local file
  while read -r file; do
    jq empty "$file" 2> /dev/null || fail "$file" "invalid JSON"
  done < <(find . -name '*.json' | sed 's|^\./||')
}

# Rules in .markdownlint-cli2.yaml. Findings come on stderr as "FILE:LINE[:COL] error RULE
# DESCRIPTION"; stdout is only a banner.
check_markdown() {
  local line
  while read -r line; do
    fail "${line%% *}" "${line#* error }"
  done < <(markdownlint-cli2 "**/*.md" 2>&1 > /dev/null || true)
}

check_container_ips() {
  local ip
  for ip in $(grep -rh --include='*.container' '^IP=' . | sort | uniq -d || true); do
    fail "$(grep -rlxF --include='*.container' "$ip" . | sed 's|^\./||' | sort | paste -sd ' ' -)" \
      "${ip} is set in more than one quadlet"
  done
}

# The image updater pulls upstream refs as written and loads them as localhost/<path>,
# which only works with an explicit registry host and namespace.
check_upstream_refs() {
  local node svc container image upstream
  while read -r node svc container image upstream; do
    [[ "$upstream" == - || "$upstream" =~ ^[^/]+\.[^/]+/[^/]+/[^/]+ ]] || \
      fail "$(inventory "$node")" "services.${svc}: upstream ${upstream} needs a registry host and namespace"
  done < <(facts image)
}

# The image updater loads images under these names, so a quadlet whose Image= differs
# would never be updated.
check_quadlet_images() {
  local node svc container image upstream script quadlet file actual
  while read -r node svc container image upstream; do
    script="src/nodes/${node}/install_svcs.sh"
    [ -f "$script" ] || continue  # check_dispatch_scripts reports it
    quadlet=$(awk -v c="${svc})" '$1 == c {f=1; next} f && /;;/ {exit} f' "$script" | \
      grep -oE "[a-zA-Z0-9_./-]+/${container}\.container" | head -n 1 || true)
    if [ -z "$quadlet" ]; then
      fail "$script" "the ${svc} case copies no ${container}.container ($(inventory "$node") services.${svc})"
      continue
    fi
    # A *.container.j2.j2 source is still *.container.j2 until install time
    file="src/${quadlet}"
    [ -f "$file" ] || file+=".j2"
    actual=$(sed -n 's/^Image=//p' "$file" 2> /dev/null || true)
    [[ "$actual" == "$image" ]] || \
      fail "$file" "Image=${actual}, expected ${image} ($(inventory "$node") services.${svc})"
  done < <(facts image)
}

# Every repo script a dispatcher runs must exist and, when it is passed a name, have
# that case. This covers services, debian_services, commands[].script and the paths in
# commands[].run.
check_dispatch_scripts() {
  local node line script arg file
  while read -r node line; do
    line=${line#sudo }
    script=${line%% *}
    arg=${line#"$script"}
    arg=${arg# }
    case $script in
      /root/homelab-rendered/src/*) file="src/${script#/root/homelab-rendered/src/}" ;;
      # upload_src.sh ships only src/nodes/router to the router, as /root/router-src
      /root/router-src/*) file="src/nodes/router/${script#/root/router-src/}" ;;
      *) continue ;;
    esac
    if [ ! -f "$file" ]; then
      fail "$file" "missing, but the ${node} dispatcher runs it"
    elif [ -n "$arg" ] && ! cases "$file" | grep -qxF -- "$arg"; then
      fail "$file" "no ${arg} case, but the ${node} dispatcher runs it"
    fi
  done < <(facts run | sort -u)
}

# The reverse of check_dispatch_scripts for install_svcs.sh: a case the inventory
# doesn't list would have no dispatcher case, sudo grant or OliveTin button.
check_install_cases() {
  local node file svc
  for node in $(facts node); do
    file="src/nodes/${node}/install_svcs.sh"
    [ -f "$file" ] || continue
    for svc in $(cases "$file"); do
      facts service | grep -qxF "${node} ${svc}" || \
        fail "$file" "the ${svc} case isn't in $(inventory "$node") services"
    done
  done
}

check_unique_subdomains() {
  local subdomain
  for subdomain in $(facts subdomain | cut -d' ' -f2 | sort | uniq -d); do
    fail "$(facts subdomain | awk -v s="$subdomain" '$2 == s {print "src/nodes/" $1 "/inventory.yml"}' | \
      sort -u | paste -sd ' ' -)" "subdomain ${subdomain} is listed more than once"
  done
}

# The subdomain lists drive DNS and SNI routing and the uptime URLs, so each must be
# routed by its node's Traefik, and every host Traefik routes must be listed, except
# on the default route.
check_routes() {
  local site node routes host listed routed subdomain
  site=$(yq '.site.url' "$all_vars")
  for node in $(facts node); do
    routes="src/nodes/${node}/traefik/routes.yml"
    [ -f "$routes" ] || continue
    listed=$(facts subdomain | sed -n "s/^${node} //p" | sort -u)
    # shellcheck disable=SC2016 # the backticks are literal regex text
    routed=$(yq --yaml-fix-merge-anchor-to-spec=true '.http.routers[].rule' "$routes" | \
      grep -oE 'Host\(`[^`]+`\)' | sed -E 's/^Host\(`//; s/`\)$//' | \
      while read -r host; do
        [[ "$host" != *".${site}" ]] || echo "${host%".${site}"}"
      done | sort -u || true)
    for subdomain in $(comm -23 <(lines "$listed") <(lines "$routed")); do
      fail "$routes" "no Host() rule for ${subdomain}, listed in $(inventory "$node") services"
    done
    [ "$node" != "$default_route_node" ] || continue
    for subdomain in $(comm -13 <(lines "$listed") <(lines "$routed")); do
      fail "$(inventory "$node")" "no service has subdomain ${subdomain}, which ${routes} routes"
    done
  done
}

# Every ungated dispatcher case gets an OliveTin button; every `ssh autoadmin@NODE CASE`
# OliveTin runs, chained or not, names a real case that OliveTin's own key may run.
check_olive_tin() {
  local config=src/services/olive_tin/config.yaml buttons referenced node name
  if [ ! -f "$config" ]; then
    fail "$config" "missing"
    return
  fi
  buttons=$(facts button | sort -u)
  referenced=$(yq '.. | select(tag == "!!map" and has("shell")) | .shell' "$config" | \
    grep -oE 'ssh autoadmin@[^ ]+ [^ &;|]+' | sed 's/^ssh autoadmin@//' | sort -u || true)
  while read -r node name; do
    fail "$config" "no button runs ${node} dispatcher case ${name}"
  done < <(comm -23 <(lines "$buttons") <(lines "$referenced"))
  while read -r node name; do
    if facts pve1_file_transfer | grep -qxF "${node} ${name}"; then
      fail "$config" "runs ssh autoadmin@${node} ${name}, a pve1 file transfer only pve1 may run"
    elif ! facts case | grep -qxF "${node} ${name}"; then
      fail "$config" "runs ssh autoadmin@${node} ${name}, which isn't a ${node} dispatcher case"
    fi
  done < <(comm -13 <(lines "$buttons") <(lines "$referenced"))
}

# upload_src.sh ships a debian node all of base/ but only the node and service dirs
# node_dirs.sh lists, in the same tree shape, so every nodes/ and services/ path it uses
# must be among them. That is every absolute (/root/homelab-rendered/src/...,
# ${rendered}/...) or ../ path in its node and service dirs, plus the src/-relative paths
# in its node dir, dispatcher lines and debian_services cases. base/ is skipped: its
# scripts serve every node and name other nodes' dirs only in what those nodes run,
# like svcs_lib.sh's traefik install.
check_upload_dirs() {
  local anchored='(homelab-rendered/src/|\$\{?rendered\}?/|\.\./)'
  local node paths path svc ref
  # Prints the nodes/ and services/ paths in stdin that follow the prefix regex $1,
  # without comment lines
  src_refs() {
    grep -v '^[[:space:]]*#' | grep -oE "$1(nodes|services)/[A-Za-z0-9_.-]+" | \
      grep -oE '(nodes|services)/[A-Za-z0-9_.-]+$' || true
  }
  for node in $(facts node); do
    if ! paths=$("${tools}/node_dirs.sh" "$node" 2>&1); then
      fail "$(inventory "$node")" "${paths#"error: $(inventory "$node"): "}"
      continue
    fi
    [ -n "$paths" ] || continue
    for ref in $(
      {
        for path in $paths; do [ "$path" == base ] || echo "src/${path}"; done | \
          xargs grep -rhI '' | src_refs "$anchored"
        {
          grep -rhI '' "src/nodes/${node}"
          facts run | sed -n "s/^${node} //p"
          for svc in $(yq '.debian_services // [] | .[]' "$(inventory "$node")"); do
            awk -v c="${svc})" '$1 == c {f=1; next} f && /;;/ {exit} f' src/base/debian/install_svcs.sh
          done
        } | src_refs "(${anchored}|^|[^A-Za-z0-9_./-])"
      } | sort -u
    ); do
      # Other paths that happen to match, like a container's /data/services/
      [ -e "src/${ref}" ] || continue
      grep -qxF "$ref" <<< "$paths" || \
        fail "$(inventory "$node")" "uses src/${ref}, which upload_src.sh doesn't ship to it; add it to a service's dirs"
    done
  done
}

check_yaml
check_json
check_markdown
check_container_ips
check_upstream_refs
check_quadlet_images
check_dispatch_scripts
check_install_cases
check_unique_subdomains
check_routes
check_olive_tin
check_upload_dirs
exit "$status"
