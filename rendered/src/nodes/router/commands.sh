#!/bin/sh
# Usage:
#   /usr/local/bin/commands.sh CMD

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin
set -eu

case "$1" in
  install_certs)
    # The certificate and key come on stdin, bundled by send_files.sh on pve1 with a
    # SHA256SUMS manifest (receive_files in src/base/lib.sh, in POSIX sh)
    dir=$(mktemp -d)
    tar -xf - -C "$dir" --no-same-owner
    for f in router.cert.pem router.key.pem; do
      sum=$(sed -n "s/^\([0-9a-f]\{64\}\)  ${f}\$/\1/p" "$dir/SHA256SUMS")
      [ -f "$dir/$f" ] && [ -n "$sum" ] && [ "$(sha256 -q "$dir/$f")" = "$sum" ] || {
        rm -rf "$dir"
        echo "error: ${f} missing or its checksum doesn't match" >&2
        exit 1
      }
    done
    mv "$dir/router.cert.pem" "$dir/router.key.pem" /root
    rm -rf "$dir"
    php /root/pfsense-import-certificate.php /root/router.cert.pem /root/router.key.pem
    ;;
  install_dispatcher)
    cp /root/router-src/sshd_extra /etc
    cp /root/router-src/sudoers /usr/local/etc/sudoers.d/dispatcher
    # Rename, not overwrite: see install_dispatcher in src/base/debian/commands.sh.j2
    cp /root/router-src/dispatcher.sh /usr/local/bin/dispatcher.sh.new
    mv /usr/local/bin/dispatcher.sh.new /usr/local/bin/dispatcher.sh

    php /etc/sshd
    service sshd onerestart
    service sshd status
    ;;
  start_pve2)
    ping -c1 -W1 192.168.2.10 && exit 0
    mac=$(cat /root/pve2_mac_address.txt)
    iface=$(ifconfig | grep -B4 "inet 192.168.2.1" | grep "RUNNING" | cut -d: -f1)
    wake "$iface" "$mac"
    # Poll until the host actually boots, BIOS + Proxmox startup can take well over 10s from cold.
    for _ in $(seq 1 60); do
      ping -c1 -W1 192.168.2.10 > /dev/null 2>&1 && break
      sleep 5
    done
    sleep 10
    ;;
  *)
    echo "Unauthorized command: $1" >&2
    exit 1
    ;;
esac
