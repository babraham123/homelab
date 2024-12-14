# PVE2 setup specific for hosting secsvcs
Initial setup for the secondary VM host, PVE2. Handles VM management services.

- Make sure that [Proxmox setup](./proxmox.md) has been completed.
- Create the websvcs VM with the desired resources and devices attached. websvcs runs the rest of the web apps on a beefier machine. All services are containerized.

## VM management
[Docs](https://pve.proxmox.com/pve-docs/qm.1.html)

- Ensure mutual exclusion between VMs that use the GPU
  - Install hook script
```bash
mkdir -p /var/lib/vz/snippets
cp src/pve2/gpu_hookscript.pl /var/lib/vz/snippets
# get IDs of GPU VMs, devtop and gaming
qm list
qm set 100 --hookscript local:snippets/gpu_hookscript.pl
qm set 102 --hookscript local:snippets/gpu_hookscript.pl
```
