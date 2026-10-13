#!/bin/sh
# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take. Commands carry data
# on stdin (install_certs), so everything the dispatcher says goes to stderr.
# Usage:
#   ssh autoadmin@router CMD

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin
set -eu

echo "Request received: '${SSH_ORIGINAL_COMMAND:-}' from ${SSH_CLIENT:-}" >&2

unauthorized() {
  echo "Unauthorized: $*" >&2
  exit 1
}

# Guards the pve1_file_transfer commands: the certificate this session logged in with
# must be pve1's. See src/base/debian/dispatcher.sh; sshd_extra sets ExposeAuthInfo.
require_pve1() {
  tmp=$(mktemp)
  grep -m1 '^publickey [^ ]*-cert-v01@openssh\.com ' "${SSH_USER_AUTH:-/dev/null}" | \
    cut -d' ' -f2- > "$tmp" || true
  id=$(ssh-keygen -L -f "$tmp" 2> /dev/null | sed -n 's/^ *Key ID: "\(.*\)"$/\1/p') || true
  rm -f "$tmp"
  [ "$id" = pve1 ] || unauthorized "key ID '${id}' may not run '${SSH_ORIGINAL_COMMAND:-}'"
}

case "${SSH_ORIGINAL_COMMAND:-}" in
  install_certs)
    require_pve1
    sudo /root/router-src/commands.sh install_certs
    ;;
  install_dispatcher)
    sudo /root/router-src/commands.sh install_dispatcher
    ;;
  start_pve2)
    sudo /root/router-src/commands.sh start_pve2
    ;;
  *)
    unauthorized "command '${SSH_ORIGINAL_COMMAND:-}'"
    ;;
esac
echo "Completed command" >&2
exit 0
