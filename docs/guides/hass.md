# Home Assistant setup
Initial setup for a Home Assistant VM.

## VM creation
- Download the [HA image](https://www.home-assistant.io/installation/alternative) and rename the extension to `.img`. Upload to Proxmox.
- Do the basic [VM setup](./vm.md)
- Use `lsusb` to detect any USB devices and pass them through to the VM [ref](https://pve.proxmox.com/wiki/USB_Devices_in_Virtual_Machines).

## Configure OS


