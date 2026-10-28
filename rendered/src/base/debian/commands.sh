#!/bin/bash
# Usage:
#   src/base/debian/commands.sh CMD
# The install_* commands take their files on stdin, bundled by send_files.sh; nothing is
# read from autoadmin's home.

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

case $1 in
  install_ssh_ca)
    # Moves SSH public keys into their respective locations and restarts sshd.
    receive_files ca_ssh_key.pub ssh_host_key_cert.pub known_hosts
    # First, so a stale rendered tree without it fails before anything is moved
    install -m 644 "${rendered}/base/debian/ssh_config" /etc/ssh/ssh_config.d/homelab.conf

    mv ca_ssh_key.pub /etc/ssh
    mv ssh_host_key_cert.pub /etc/ssh
    mv known_hosts /etc/ssh/ssh_known_hosts

    systemctl restart sshd
    systemctl status sshd --no-pager
    ;;
  install_dispatcher)
    # First: a broken sudoers file breaks sudo for every user on the node
    visudo -cf "${rendered}/base/debian/sudoers"
    # This runs inside dispatcher.sh, which bash reads incrementally. Overwriting
    # it in place makes bash resume at the old byte offset in the new file; a
    # rename gives the new script its own inode and leaves the running one intact.
    install_lib
    cp "${rendered}/base/debian/dispatcher.sh" /usr/local/bin/dispatcher.sh.new
    mv /usr/local/bin/dispatcher.sh.new /usr/local/bin/dispatcher.sh
    cp "${rendered}/base/debian/autoadmin_sshd.conf" /etc/ssh/sshd_config.d
    cp "${rendered}/base/debian/sudoers" /etc/sudoers.d/dispatcher

    systemctl restart sshd
    systemctl status sshd --no-pager
    ;;
  # Anything not running: failed units, and containers that exited or are unhealthy
  failed_units)
    systemctl list-units --failed --no-pager
    if command -v podman > /dev/null; then
      podman ps -a --filter status=exited --filter status=created --filter health=unhealthy \
        --format '{{.Names}}\t{{.Status}}'
    fi
    ;;
  # The nightly scanned update, now (base/podman/image_updater.service)
  update_images)
    systemctl start image_updater
    systemctl status image_updater --no-pager
    ;;
  reboot)
    systemctl reboot
    ;;
  # Everything unattended-upgrades leaves out (docs/maintenance.md)
  upgrade)
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
    DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
    if [ -f /var/run/reboot-required ]; then
      echo "reboot required: ssh autoadmin@$(hostname) reboot"
    fi
    ;;
  install_ca)
    receive_files ca-chain.cert.pem
    mv ca-chain.cert.pem /etc/ssl/certs/janedoe.com.ca_chain.cert.pem
    ;;
  copy_acme_certs)
    # Only for hosts running traefik: the file on stdout, for acme_transfer.sh on pve1
    cat /etc/opt/traefik/certificates/acme.json
    ;;
  *)
    die "unknown file type: $1"
    ;;
esac
