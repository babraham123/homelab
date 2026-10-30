# shellcheck shell=bash
# tools/inventory.py over tests/fixtures/nodes/<node>/inventory.yml, as templates read it
# (inv.<name>). Expected lists follow ADR 0006 and the tools/inventory.py header: nodes in name order; cases in the order
# debian_services, services (install order; shared ones run src/base/podman's script),
# install_all_svcs, install_some_svcs, commands, triggers;
# sudoers holds the sorted, unique sudo lines without `sudo `; scripts live under
# /root/homelab-rendered/src, except the router's under /root/router-src.
# shellcheck source=tests/lib.sh
source tests/lib.sh

inventory=tests/fixtures/nodes

test_dispatcher_cases() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for node in nodes -%}
# {{ node }}
{{ inv.cases[node] }}
{% endfor -%}
EOF
)
  assert_eq "$out" <<'EOF'
# alpha
  install_node_exporter)
    sudo /root/homelab-rendered/src/base/debian/install_svcs.sh node_exporter
    ;;
  install_mdns_repeater)
    sudo /root/homelab-rendered/src/base/debian/install_svcs.sh mdns_repeater
    ;;
  install_zeta)
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh zeta
    ;;
  install_proxy)
    sudo /root/homelab-rendered/src/base/podman/install_svcs.sh proxy
    ;;
  install_app)
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh app
    ;;
  install_pod)
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh pod
    ;;
  install_plain)
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh plain
    ;;
  install_all_svcs)
    sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
    sudo /root/homelab-rendered/src/base/debian/install_svcs.sh node_exporter
    sudo /root/homelab-rendered/src/base/debian/install_svcs.sh mdns_repeater
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh zeta
    sudo /root/homelab-rendered/src/base/podman/install_svcs.sh proxy
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh app
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh pod
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh plain
    sudo /root/homelab-rendered/src/base/debian/commands.sh failed_units
    ;;
  install_some_svcs)
    sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
    sudo /root/homelab-rendered/src/base/debian/install_svcs.sh mdns_repeater
    sudo /root/homelab-rendered/src/base/podman/install_svcs.sh proxy
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh plain
    sudo /root/homelab-rendered/src/base/debian/commands.sh failed_units
    ;;
  install_keys)
    require_pve1
    sudo /root/homelab-rendered/src/nodes/alpha/commands.sh install_keys
    ;;
  build_map)
    /root/homelab-rendered/src/nodes/alpha/commands.sh build_map
    ;;
  check_gpu)
    sudo /usr/bin/systemctl status nvidia-persistenced --no-pager
    nvidia-smi
    ;;
  backup)
    sudo /root/homelab-rendered/src/nodes/alpha/backup.sh
    ;;
  install_ca)
    sudo /root/homelab-rendered/src/base/debian/commands.sh install_ca
    ;;
  install_dispatcher)
    sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
    ;;
  failed_units)
    sudo /root/homelab-rendered/src/base/debian/commands.sh failed_units
    ;;
# gaming
  StartSunshine)
    ;;
  StopSunshine)
    ;;
# router
  install_certs)
    sudo /root/router-src/commands.sh install_certs
    ;;
EOF
}

# Only sudo lines are granted: build_map (sudo: false) and nvidia-smi are not
test_sudoers() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for node in nodes -%}
# {{ node }}
{% for cmd in inv.sudo_cmds[node] -%}
{{ cmd }}
{% endfor -%}
{% endfor -%}
EOF
)
  assert_eq "$out" <<'EOF'
# alpha
/root/homelab-rendered/src/base/debian/commands.sh failed_units
/root/homelab-rendered/src/base/debian/commands.sh install_ca
/root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
/root/homelab-rendered/src/base/debian/install_svcs.sh mdns_repeater
/root/homelab-rendered/src/base/debian/install_svcs.sh node_exporter
/root/homelab-rendered/src/base/podman/install_svcs.sh proxy
/root/homelab-rendered/src/nodes/alpha/backup.sh
/root/homelab-rendered/src/nodes/alpha/commands.sh install_keys
/root/homelab-rendered/src/nodes/alpha/install_svcs.sh app
/root/homelab-rendered/src/nodes/alpha/install_svcs.sh plain
/root/homelab-rendered/src/nodes/alpha/install_svcs.sh pod
/root/homelab-rendered/src/nodes/alpha/install_svcs.sh zeta
/usr/bin/systemctl status nvidia-persistenced --no-pager
# gaming
# router
/root/router-src/commands.sh install_certs
EOF
}

# Buttons follow case order and skip pve1_file_transfer cases (install_keys)
test_olive_tin_buttons() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for node in nodes -%}
{{ node }}: {{ inv.dispatch[node] | map(attribute='name') | join(' ') }}
{{ node }} buttons: {{ inv.buttons[node] | join(' ') }}
{% endfor -%}
EOF
)
  assert_eq "$out" <<'EOF'
alpha: install_node_exporter install_mdns_repeater install_zeta install_proxy install_app install_pod install_plain install_all_svcs install_some_svcs install_keys build_map check_gpu backup install_ca install_dispatcher failed_units
alpha buttons: install_node_exporter install_mdns_repeater install_zeta install_proxy install_app install_pod install_plain install_all_svcs install_some_svcs build_map check_gpu backup install_ca install_dispatcher failed_units
gaming: StartSunshine StopSunshine
gaming buttons: StartSunshine StopSunshine
router: install_certs
router buttons: install_certs
EOF
}

# Uptime: path / unless given (Authelia matches the Gatus audience to the exact URL), tier 2,
# the Authelia bearer token and no extra conditions unless given
test_subdomains_and_uptime() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for node in nodes -%}
{{ ([node ~ ':'] + inv.subdomains[node]) | join(' ') }}
{% endfor -%}
admin: {{ inv.admin_subdomains | join(' ') }}
{% for u in inv.uptime -%}
{{ u.name }} | {{ u.node }} | {{ u.url }} | {{ u.tier }} | {{ u.conditions }} | {{ u.oauth }}
{% endfor -%}
EOF
)
  assert_eq "$out" <<'EOF'
alpha: app z
gaming:
router:
admin: z
zeta | alpha | https://z.example.com/ | 2 | [] | True
app health | alpha | https://app.example.com/health | 1 | ['[BODY].status == OK'] | False
EOF
}

# Install order, update_last entries moved to the end; upstream images load as
# localhost/ + the ref without its registry host, built ones as localhost/<build>:latest
test_image_update_order() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for i in inv.images.alpha -%}
{{ i.service }} {{ i.container }} {{ i.image }}
{% endfor -%}
EOF
)
  assert_eq "$out" <<'EOF'
zeta zeta localhost/library/nginx:stable
pod pod-web localhost/pod-web:latest
app app localhost/app:latest
pod pod-db localhost/acme/db:16
EOF
}

# ufw rules from open_ports, in port order: a container source by its address on the bridge,
# a node source by its vars.yml ip
test_ufw_rules() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for node in nodes -%}
{{ node }}: {{ inv.ufw[node] }}
{% endfor -%}
EOF
)
  assert_eq "$out" <<'EOF'
alpha: [{'port': 5201, 'from': '192.0.2.1', 'bridge': False}, {'port': 9633, 'from': '10.9.0.5', 'bridge': True}]
gaming: []
router: []
EOF
}

# Addresses: the node's container_subnet plus each ip, keyed by quadlet name, so a
# `containers` entry has its own
test_container_addrs() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for node in nodes -%}
{{ node }}: {{ inv.addr[node] }}
{% endfor -%}
EOF
)
  assert_eq "$out" <<'EOF'
alpha: {'zeta': '10.9.0.5', 'pod-db': '10.9.0.7'}
gaming: {}
router: {}
EOF
}

# A misspelled, mistyped or lone key fails the derivation, naming every one: a file's
# shape first (alpha), then the keys that only make sense together (beta)
test_shape_errors() {
  mkdir -p "${tmp}/bad/alpha" "${tmp}/bad/beta"
  cat > "${tmp}/bad/alpha/inventory.yml" <<'EOF'
debian_services: [node_exporter, Node-Exporter]
services:
  web:
    ip: 1
    upstream: library/nginx:stable
    uptime_teir: 1
    uptime_tier: 3
    shared: false
  db: [a]
open_ports: {70000: [web]}
image_updater_slot: 21:00
commands: {name: x}
EOF
  cat > "${tmp}/bad/beta/inventory.yml" <<'EOF'
services:
  app:
    uptime: app
    uptime_tier: 1
  pod:
    ip: 5
    containers:
      pod-db: {upstream: ghcr.io/a/db:1, build: db}
  solo:
    subdomain: s
    uptime_oauth: false
commands:
  - {script: base/debian/commands.sh, run: [ls]}
  - {name: ls, run: [ls], sudo: false}
  - {name: nothing}
EOF
  if out=$(template_vars "${tmp}/bad" < tests/fixtures/site.yml 2>&1 > /dev/null); then
    flunk "template_vars passed, expected shape errors"
  fi
  assert_eq "$out" <<'EOF'
error: src/nodes/alpha/inventory.yml: debian_services[1]: 'Node-Exporter' isn't a string matching [a-z0-9_-]+
error: src/nodes/alpha/inventory.yml: services.web.ip: 1 isn't an integer from 2 to 254
error: src/nodes/alpha/inventory.yml: services.web.upstream: 'library/nginx:stable' isn't a string matching [^/]+\.[^/]+/[^/]+/[^/]+
error: src/nodes/alpha/inventory.yml: services.web.uptime_teir: unknown key
error: src/nodes/alpha/inventory.yml: services.web.uptime_tier: 3 isn't one of [1, 2]
error: src/nodes/alpha/inventory.yml: services.web.shared: False isn't true, the only value it takes
error: src/nodes/alpha/inventory.yml: services.db: ['a'] isn't a mapping
error: src/nodes/alpha/inventory.yml: open_ports.70000: 70000 isn't an integer from 1 to 65535
error: src/nodes/alpha/inventory.yml: image_updater_slot: 1260 isn't a string matching ([01][0-9]|2[0-3]):[0-5][0-9]
error: src/nodes/alpha/inventory.yml: commands: {'name': 'x'} isn't a list
error: src/nodes/beta/inventory.yml: services.app: uptime needs subdomain
error: src/nodes/beta/inventory.yml: services.pod: containers replaces ip
error: src/nodes/beta/inventory.yml: services.pod: pod-db is either pulled (upstream) or built (build), not both
error: src/nodes/beta/inventory.yml: services.solo: uptime_oauth needs uptime
error: src/nodes/beta/inventory.yml: commands[0]: needs a name
error: src/nodes/beta/inventory.yml: commands[0]: runs either a script or run lines, not both or neither
error: src/nodes/beta/inventory.yml: commands.ls: sudo only applies to a script
error: src/nodes/beta/inventory.yml: commands.nothing: runs either a script or run lines, not both or neither
EOF
}

test_shared_services() {
  out=$(render_inventory "$inventory" <<'EOF'
shared: {{ inv.shared.alpha | join(' ') }}
EOF
)
  assert_eq "$out" <<'EOF'
shared: proxy
EOF
}
