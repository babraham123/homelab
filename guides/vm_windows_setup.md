# Windows VM setup

- First do the basic [vm_setup.md](./vm_setup.md)

### Images
- Download the Windows [ISO](https://www.microsoft.com/software-download/windows11)
- Download the Windows VirtIO [drivers](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)
- Upload ISOs to Proxmox on "local"

### Configure VM
[src](https://www.wundertech.net/how-to-install-windows-11-on-proxmox/), [vid](https://www.youtube.com/watch?v=fupuTkkKPDU)
- Turn on
	- For driver ISO, if IDE1 doesn't work use SATA0
	- If boot fails
		- `exit` UEFI shell
		- Set [UEFI Boot Entry](https://pve.proxmox.com/wiki/OVMF/UEFI_Boot_Entries)
- Install VirtIO drivers (virtscsi, netkvm, balloon)
- Login with `a@a.com` for local acct
- Install rest of drivers
	- ISO drive > `virtio-win-gt-x64`, double click, install
- Setup RDP
	- In Start menu search for `remote desktop settings`, enable
	- On mac, install `Microsoft Remote Desktop`, verify connection
		- username = `windows11-1\{{ username }}`, login password
- Install apps
	- Launch shell (win R, `PowerShell`, ctrl shift enter)
```powershell
winget install -e -h --accept-source-agreements --accept-package-agreements --id 7zip.7zip
winget install -e -h --accept-source-agreements --accept-package-agreements --id Adobe.Acrobat.Reader.64-bit
winget install -e -h --accept-source-agreements --accept-package-agreements --id Google.Chrome
winget install -e -h --accept-source-agreements --accept-package-agreements --id JanDeDobbeleer.OhMyPosh
winget install -e -h --accept-source-agreements --accept-package-agreements --id Microsoft.PowerToys
winget install -e -h --accept-source-agreements --accept-package-agreements --id Notepad++.Notepad++
winget install -e -h --accept-source-agreements --accept-package-agreements --id PuTTY.PuTTY
winget install -e -h --accept-source-agreements --accept-package-agreements --id Valve.Steam
```
- Install SSH ([src](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell))
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
```
- Shutdown VM

### GPU Passthrough
[src](https://3os.org/infrastructure/proxmox/gpu-passthrough/gpu-passthrough-to-vm/#proxmox-configuration-for-gpu-passthrough), [vid](https://www.youtube.com/watch?v=fgx3NMk6F54)
- Follow the steps listed in [proxmox_setup.md](./proxmox_setup.md#pci-passthrough)
- Create VM, add PCI Device
- Install Geforce Experience
	- Open NVIDIA Control Panel, test 3D acceleration

### SSH
- `vi ~/.ssh/config`
- Example commands
	- `ssh -l "{{ username }}" {{ gaming.ip }}`
```Powershell
TODO: figure out cmds
```
	- `scp file.txt gaming:'"/c:/Users/{{ username }}/Documents/file.txt"'`

