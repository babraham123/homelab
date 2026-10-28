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
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh zeta
    sudo /root/homelab-rendered/src/base/podman/install_svcs.sh proxy
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh app
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh pod
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh plain
    ;;
  install_some_svcs)
    sudo /root/homelab-rendered/src/base/podman/install_svcs.sh proxy
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh plain
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
/root/homelab-rendered/src/base/debian/commands.sh install_ca
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
alpha: install_node_exporter install_mdns_repeater install_zeta install_proxy install_app install_pod install_plain install_all_svcs install_some_svcs install_keys build_map check_gpu backup install_ca
alpha buttons: install_node_exporter install_mdns_repeater install_zeta install_proxy install_app install_pod install_plain install_all_svcs install_some_svcs build_map check_gpu backup install_ca
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

# render_host.sh's data: only nodes with a container_subnet (alpha, in site.yml), with
# their inventory services and addresses
test_host_vars() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for node, h in inv.host_vars.items() -%}
{{ node }}: {{ h.node }} {{ h.services | list | join(' ') }} {{ h.addr | list | join(' ') }}
{% endfor -%}
shared: {{ inv.shared.alpha | join(' ') }}
EOF
)
  assert_eq "$out" <<'EOF'
alpha: alpha zeta proxy app pod plain zeta pod-db
shared: proxy
EOF
}
