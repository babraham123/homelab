# General Proxmox VM setup

## pfSense
- Create a static DHCP lease
  - Go to Services >> DHCP Server >> DHCP Static Mappings

- Add a DNS record
  - Update `unbound.conf`
  - Go to Services >> DNS Resolver >> Custom options, paste in config
