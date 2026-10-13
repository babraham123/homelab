# PVE2 setup specific for hosting websvcs, devtop, gaming and PBS

Initial setup for the secondary VM host, PVE2. Handles VM management services.

- Make sure that [Proxmox setup](./proxmox.md) has been completed.
- Create the websvcs VM with the desired resources and devices attached

## VM management

[Docs](https://pve.proxmox.com/pve-docs/qm.1.html)

- Install the GPU hook script on devtop and gaming, so only one runs at a time
  - Rerun after any deploy that changes `src/nodes/pve2/hookscript.pl`

```bash
ssh autoadmin@pve2 install_hookscript
```

## Automation

- Programmatically send WoL packets from the router

```bash
ip -br link show | grep -E '^(en|eth)' | awk '{print $3}' > pve2_mac_address.txt
scp pve2_mac_address.txt admin@router:/root
rm pve2_mac_address.txt
```
