# 07. Managed PoE switch; enable wired VLANs 20 and 21

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-14

## Problem

The wired VLANs are defined but not enforced: they wait on a managed switch
(`docs/networking.md` "VLANs", `docs/security.md` "Known gaps"). A wired or PoE camera
can't be isolated until then. This ticket only blocks 01 if the camera is wired.

## Change

1. **Buy** a switch with 802.1Q VLANs and PoE+ on enough ports for cameras and APs.
   The planned 24-port PoE+ switch in `docs/architecture.md` fits. Make sure its
   management UI can sit on a trusted VLAN only.
2. **Trunk** from pfSense's LAN2 NIC to the switch, carrying VLANs 20 (WiredTrusted)
   and 21 (WiredIoT) tagged. Leave LAN2 untagged only if something still needs it.
3. **Access ports:** camera ports untagged on 21 with PoE on; everything else on 20.
4. **pfSense:**
   - enable the VLAN 20/21 interfaces and DHCP;
   - copy the WiFi VLAN rules: IoT → trusted blocked by default, allowlisted services
     only;
   - add VLAN 21 to the `cameras` rules from 02.
5. **Docs:**
   - `docs/networking.md`: VLAN table status `planned` → `active`;
   - `docs/architecture.md`: the switch row;
   - `docs/security.md`: drop "Wired VLAN enforcement waits on a managed switch".

## Acceptance

- A device on a VLAN 21 access port gets a `192.168.21.x` lease and can't reach
  `192.168.20.0/24`, `192.168.10.0/24` or the service VMs, except through 02's rules.
- A device on VLAN 20 reaches the service VMs as before.
- The switch's management UI is reachable only from trusted VLANs.

## Comments
