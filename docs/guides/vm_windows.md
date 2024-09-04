# Windows VM setup
Guide to create a Windows VM. 

- First do the basic [VM setup](./vm.md)

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
		- username = `windows11-gaming\{{ username }}`, login password
  - Disable login, [ref](https://answers.microsoft.com/en-us/windows/forum/all/how-to-login-automatically-to-windows-11/c0e9301e-392e-445a-a5cb-f44d00289715)
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
- Follow the steps in [Proxmox > PCI passthrough](./proxmox.md#pci-passthrough)
- Create VM, add PCI Device
- Install Geforce Experience
	- Open NVIDIA Control Panel, test 3D acceleration

### SSH
- `vi ~/.ssh/config`
- Example commands
	- `ssh -l "{{ username }}" gaming.{{ site.url }}`
```Powershell
# TODO: add more cmds
shutdown /r
```
	- `scp file.txt gaming.{{ site.url }}:'"/c:/Users/{{ username }}/Documents/file.txt"'`
