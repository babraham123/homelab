#!/bin/bash
# SSH Forced Command Dispatcher, shared by the Debian nodes
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take, from this node's
# cases: the hostname is the node name. Commands carry data on stdin (file installs)
# and stdout (backup, copy_acme_certs), so everything the dispatcher says goes to stderr.
# Usage:
#   ssh autoadmin@NODE CMD

# shellcheck source=src/base/lib.sh
source /usr/local/lib/homelab/lib.sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}" >&2

unauthorized() {
  echo "Unauthorized: $*" >&2
  exit 1
}

# Guards the pve1_file_transfer commands: the certificate this session logged in with
# must be pve1's (key ID "pve1", ssh_cert_gen.sh's -I). sshd writes the credential that
# authenticated the session to $SSH_USER_AUTH (ExposeAuthInfo in autoadmin_sshd.conf),
# the whole certificate for a certificate login.
require_pve1() {
  local tmp id
  tmp=$(mktemp)
  grep -m1 '^publickey [^ ]*-cert-v01@openssh\.com ' "${SSH_USER_AUTH:-/dev/null}" | \
    cut -d' ' -f2- > "$tmp" || true
  id=$(ssh-keygen -L -f "$tmp" 2> /dev/null | sed -n 's/^ *Key ID: "\(.*\)"$/\1/p' || true)
  rm -f "$tmp"
  [[ $id == pve1 ]] || unauthorized "key ID '${id}' may not run '${SSH_ORIGINAL_COMMAND:-}'"
}

case "$(hostname)" in
  devtop)
    case "${SSH_ORIGINAL_COMMAND:-}" in
      install_nvidia_gpu_exporter)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh nvidia_gpu_exporter
        ;;
      check_gpu)
        sudo /usr/bin/systemctl status nvidia-persistenced --no-pager
        nvidia-smi
        ;;
      install_ssh_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ssh_ca
        ;;
      host_key)
        cat /etc/ssh/ssh_host_ed25519_key.pub
        ;;
      install_dispatcher)
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
        ;;
      install_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ca
        ;;
      *)
        unauthorized "command '${SSH_ORIGINAL_COMMAND:-}'"
        ;;
    esac
    ;;
  homesvcs)
    case "${SSH_ORIGINAL_COMMAND:-}" in
      install_mdns_repeater)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh mdns_repeater
        ;;
      install_node_exporter)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh node_exporter
        ;;
      install_image_updater)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh image_updater
        ;;
      install_traefik)
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh traefik
        ;;
      install_crowdsec_appsec)
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh crowdsec_appsec
        ;;
      install_vmagent)
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh vmagent
        ;;
      install_mosquitto)
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh mosquitto
        ;;
      install_zigbee2mqtt)
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh zigbee2mqtt
        ;;
      install_home_assistant)
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh home_assistant
        ;;
      install_fluentbit)
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh fluentbit
        ;;
      install_all_svcs)
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh traefik
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh crowdsec_appsec
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh vmagent
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh mosquitto
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh zigbee2mqtt
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh home_assistant
        sudo /root/homelab-rendered/src/nodes/homesvcs/install_svcs.sh fluentbit
        ;;
      install_keys)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/homesvcs/commands.sh install_keys
        ;;
      install_certs)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/homesvcs/commands.sh install_certs
        ;;
      backup)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/homesvcs/backup.sh
        ;;
      install_ssh_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ssh_ca
        ;;
      host_key)
        cat /etc/ssh/ssh_host_ed25519_key.pub
        ;;
      install_dispatcher)
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
        ;;
      install_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ca
        ;;
      copy_acme_certs)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh copy_acme_certs
        ;;
      *)
        unauthorized "command '${SSH_ORIGINAL_COMMAND:-}'"
        ;;
    esac
    ;;
  pve1)
    case "${SSH_ORIGINAL_COMMAND:-}" in
      install_vm_watchdog)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh vm_watchdog
        ;;
      install_cert_notifier)
        sudo /root/homelab-rendered/src/nodes/pve1/install_svcs.sh cert_notifier
        ;;
      install_backup_orchestrator)
        sudo /root/homelab-rendered/src/nodes/pve1/install_svcs.sh backup_orchestrator
        ;;
      archive_repo)
        sudo /root/homelab-rendered/src/nodes/pve1/commands.sh archive_repo
        ;;
      backup_now)
        sudo /root/homelab-rendered/src/nodes/pve1/commands.sh backup_now
        ;;
      skip_next_backup)
        sudo /root/homelab-rendered/src/nodes/pve1/commands.sh skip_next_backup
        ;;
      install_ssh_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ssh_ca
        ;;
      host_key)
        cat /etc/ssh/ssh_host_ed25519_key.pub
        ;;
      install_dispatcher)
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
        ;;
      install_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ca
        ;;
      *)
        unauthorized "command '${SSH_ORIGINAL_COMMAND:-}'"
        ;;
    esac
    ;;
  pve2)
    case "${SSH_ORIGINAL_COMMAND:-}" in
      install_vm_watchdog)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh vm_watchdog
        ;;
      install_certs_and_keys)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/pve2/commands.sh install_certs_and_keys
        ;;
      start_gaming_vm)
        sudo /root/homelab-rendered/src/nodes/pve2/commands.sh start_gaming_vm
        ;;
      stop_gaming_vm)
        sudo /root/homelab-rendered/src/nodes/pve2/commands.sh stop_gaming_vm
        ;;
      install_hookscript)
        sudo /root/homelab-rendered/src/nodes/pve2/commands.sh install_hookscript
        ;;
      backup)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/pve2/backup.sh
        ;;
      prune)
        sudo /root/homelab-rendered/src/nodes/pve2/prune.sh
        ;;
      shutdown)
        sudo /usr/sbin/shutdown -h now
        ;;
      install_ssh_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ssh_ca
        ;;
      host_key)
        cat /etc/ssh/ssh_host_ed25519_key.pub
        ;;
      install_dispatcher)
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
        ;;
      install_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ca
        ;;
      *)
        unauthorized "command '${SSH_ORIGINAL_COMMAND:-}'"
        ;;
    esac
    ;;
  secsvcs)
    case "${SSH_ORIGINAL_COMMAND:-}" in
      install_mdns_repeater)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh mdns_repeater
        ;;
      install_node_exporter)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh node_exporter
        ;;
      install_image_updater)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh image_updater
        ;;
      install_postgres)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh postgres
        ;;
      install_lldap)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh lldap
        ;;
      install_authelia)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh authelia
        ;;
      install_traefik)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh traefik
        ;;
      install_victoriametrics)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh victoriametrics
        ;;
      install_victorialogs)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh victorialogs
        ;;
      install_gatus)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh gatus
        ;;
      install_vmalert)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh vmalert
        ;;
      install_alertmanager)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh alertmanager
        ;;
      install_ntfy-alertmanager)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh ntfy-alertmanager
        ;;
      install_ntfy)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh ntfy
        ;;
      install_grafana)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh grafana
        ;;
      install_vaultwarden)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh vaultwarden
        ;;
      install_olive_tin)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh olive_tin
        ;;
      install_crowdsec)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh crowdsec
        ;;
      install_crowdsec_appsec)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh crowdsec_appsec
        ;;
      install_fluentbit)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh fluentbit
        ;;
      install_all_svcs)
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh postgres
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh lldap
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh authelia
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh traefik
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh victoriametrics
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh victorialogs
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh gatus
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh vmalert
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh alertmanager
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh ntfy-alertmanager
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh ntfy
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh grafana
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh vaultwarden
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh olive_tin
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh crowdsec
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh crowdsec_appsec
        sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh fluentbit
        ;;
      install_keys)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/secsvcs/commands.sh install_keys
        ;;
      install_certs)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/secsvcs/commands.sh install_certs
        ;;
      install_ssh_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ssh_ca
        ;;
      host_key)
        cat /etc/ssh/ssh_host_ed25519_key.pub
        ;;
      install_dispatcher)
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
        ;;
      install_olive_tin_cert)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/secsvcs/commands.sh install_olive_tin_cert
        ;;
      install_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ca
        ;;
      copy_acme_certs)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh copy_acme_certs
        ;;
      backup)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/secsvcs/backup.sh
        ;;
      *)
        unauthorized "command '${SSH_ORIGINAL_COMMAND:-}'"
        ;;
    esac
    ;;
  vpnsvcs)
    case "${SSH_ORIGINAL_COMMAND:-}" in
      install_node_exporter)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh node_exporter
        ;;
      install_image_updater)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh image_updater
        ;;
      install_fail2ban)
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh fail2ban
        ;;
      install_headscale)
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh headscale
        ;;
      install_tailscaled)
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh tailscaled
        ;;
      install_haproxy)
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh haproxy
        ;;
      install_crowdsec_firewall_bouncer)
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh crowdsec_firewall_bouncer
        ;;
      install_deadman)
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh deadman
        ;;
      install_fluentbit)
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh fluentbit
        ;;
      install_vmagent)
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh vmagent
        ;;
      install_geoip_generator)
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/install_svcs.sh geoip_generator
        ;;
      backup)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/vpnsvcs/backup.sh
        ;;
      install_ssh_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ssh_ca
        ;;
      host_key)
        cat /etc/ssh/ssh_host_ed25519_key.pub
        ;;
      install_dispatcher)
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
        ;;
      install_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ca
        ;;
      *)
        unauthorized "command '${SSH_ORIGINAL_COMMAND:-}'"
        ;;
    esac
    ;;
  websvcs)
    case "${SSH_ORIGINAL_COMMAND:-}" in
      install_mdns_repeater)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh mdns_repeater
        ;;
      install_node_exporter)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh node_exporter
        ;;
      install_nvidia_gpu_exporter)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh nvidia_gpu_exporter
        ;;
      install_image_updater)
        sudo /root/homelab-rendered/src/base/debian/install_svcs.sh image_updater
        ;;
      install_traefik)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh traefik
        ;;
      install_crowdsec_appsec)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh crowdsec_appsec
        ;;
      install_vmagent)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh vmagent
        ;;
      install_nginx)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh nginx
        ;;
      install_homepage)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh homepage
        ;;
      install_isso)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh isso
        ;;
      install_guacamole)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh guacamole
        ;;
      install_guacd)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh guacd
        ;;
      install_fluentbit)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh fluentbit
        ;;
      install_snapraid)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh snapraid
        ;;
      install_linkding)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh linkding
        ;;
      install_readeck)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh readeck
        ;;
      install_storyteller)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh storyteller
        ;;
      install_calliope)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh calliope
        ;;
      install_bookmark_handoff)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh bookmark_handoff
        ;;
      install_all_svcs)
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh traefik
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh crowdsec_appsec
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh vmagent
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh nginx
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh homepage
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh isso
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh guacamole
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh guacd
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh fluentbit
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh snapraid
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh linkding
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh readeck
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh storyteller
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh calliope
        sudo /root/homelab-rendered/src/nodes/websvcs/install_svcs.sh bookmark_handoff
        ;;
      install_keys)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/websvcs/commands.sh install_keys
        ;;
      install_certs)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/websvcs/commands.sh install_certs
        ;;
      backup)
        require_pve1
        sudo /root/homelab-rendered/src/nodes/websvcs/backup.sh
        ;;
      install_ssh_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ssh_ca
        ;;
      host_key)
        cat /etc/ssh/ssh_host_ed25519_key.pub
        ;;
      install_dispatcher)
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_dispatcher
        ;;
      install_ca)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh install_ca
        ;;
      copy_acme_certs)
        require_pve1
        sudo /root/homelab-rendered/src/base/debian/commands.sh copy_acme_certs
        ;;
      *)
        unauthorized "command '${SSH_ORIGINAL_COMMAND:-}'"
        ;;
    esac
    ;;
  *)
    unauthorized "command '${SSH_ORIGINAL_COMMAND:-}'"
    ;;
esac
echo "Completed command" >&2
exit 0
