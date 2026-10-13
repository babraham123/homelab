# shellcheck shell=bash
# src/nodes.jinja over tests/fixtures/nodes/<node>/inventory.yml. Expected lists follow
# ADR 0006 and the src/nodes.jinja header: nodes in name order; cases in the order
# debian_services, services (install order), install_all_svcs, commands, triggers;
# sudoers holds the sorted, unique sudo lines without `sudo `; scripts live under
# /root/homelab-rendered/src, except the router's under /root/router-src.
# shellcheck source=tests/lib.sh
source tests/lib.sh

inventory=tests/fixtures/nodes

test_dispatcher_cases() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for node in nodes -%}
# {{ node }}
{{ inv.cases(node) }}
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
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh app
    sudo /root/homelab-rendered/src/nodes/alpha/install_svcs.sh pod
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
{{ node }}: {{ inv.commands[node] | join(' ') }}
{{ node }} buttons: {{ inv.buttons[node] | join(' ') }}
{% endfor -%}
EOF
)
  assert_eq "$out" <<'EOF'
alpha: install_node_exporter install_mdns_repeater install_zeta install_app install_pod install_plain install_all_svcs install_keys build_map check_gpu backup install_ca
alpha buttons: install_node_exporter install_mdns_repeater install_zeta install_app install_pod install_plain install_all_svcs build_map check_gpu backup install_ca
gaming: StartSunshine StopSunshine
gaming buttons: StartSunshine StopSunshine
router: install_certs
router buttons: install_certs
EOF
}

# Uptime: tier 2 and no extra conditions unless given
test_subdomains_and_uptime() {
  out=$(render_inventory "$inventory" <<'EOF'
{% for node in nodes -%}
{{ ([node ~ ':'] + inv.subdomains[node]) | join(' ') }}
{% endfor -%}
admin: {{ inv.admin_subdomains | join(' ') }}
{% for u in inv.uptime -%}
{{ u.name }} | {{ u.host }} | {{ u.url }} | {{ u.tier }} | {{ u.conditions }}
{% endfor -%}
EOF
)
  assert_eq "$out" <<'EOF'
alpha: app z
gaming:
router:
admin: z
zeta | z.example.com | https://z.example.com | 2 | []
app health | app.example.com | https://app.example.com/health | 1 | ['[BODY].status == OK']
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
