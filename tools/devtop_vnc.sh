#!/bin/bash
# Opens devtop's VNC display through an SSH tunnel to pve2, where QEMU serves it on loopback
# only (docs/guides/devtop.md). The tunnel stays up until Ctrl+C. Logs in as manualadmin:
# autoadmin's sshd config forbids forwarding.
# Usage:
#   tools/devtop_vnc.sh

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ip=$(yq --yaml-fix-merge-anchor-to-spec=true ".devtop.ip" vars.yml)
# QEMU's display number is the last octet of devtop's IP (docs/guides/devtop.md)
port=$((5900 + ${ip##*.}))
password=$(yq --yaml-fix-merge-anchor-to-spec=true ".devtop.vnc_password" vars.yml)

if nc -z localhost "$port" 2> /dev/null; then
  warn "localhost:${port} is already listening; using it as the tunnel"
  open "vnc://:${password}@localhost:${port}"
  exit
fi

ssh -N -o ExitOnForwardFailure=yes -L "${port}:127.0.0.1:${port}" manualadmin@pve2 &
tunnel=$!
trap 'kill "$tunnel" 2> /dev/null' EXIT

for _ in {1..20}; do
  nc -z localhost "$port" 2> /dev/null && break
  kill -0 "$tunnel" 2> /dev/null || die "ssh to pve2 failed"
  sleep 0.5
done
nc -z localhost "$port" 2> /dev/null || die "tunnel to localhost:${port} didn't come up"

open "vnc://:${password}@localhost:${port}"
echo "Tunnel open on localhost:${port}; Ctrl+C closes it"
wait "$tunnel"
