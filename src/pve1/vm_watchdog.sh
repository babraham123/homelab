#!/usr/bin/env bash
# Checks proxmox for any frozen VMs and resets them.
# Usage:
#   /usr/local/bin/vm_watchdog.sh
# Ref:
# https://github.com/rtadams89/ProxmoxVMMonitoring/blob/main/reset_frozen_vms.sh
# https://pve.proxmox.com/pve-docs/qm.1.html

set -euo pipefail

finish=0
trap 'finish=1' SIGTERM

while (( finish != 1 ))
do
  runningvms=$(qm list --full | grep -v 'VMID' | grep 'running' | awk '{ print $1 }')
  for vmid in $runningvms
  do
    if ! [[ -f "/tmp/$vmid.lastup" ]]
    then
      touch "/tmp/$vmid.lastup"
    fi

    if qm agent "$vmid" ping
    then
      touch "/tmp/$vmid.lastup"
    else
      timestamp="$(date -r /tmp/$vmid.lastup +%s)" 
      lookback="$(date -d "1 minute ago" +%s)"
      if [[ "${timestamp}" -lt "${lookback}" ]]
      then
        echo "VM $vmid has been frozen for 1 minute, resetting"
        qm stop "$vmid"
        rm -f "/tmp/$vmid.lastup"
        qm wait "$vmid" --timeout 20
        qm start "$vmid"
      fi
    fi
  done
  sleep 15
done
