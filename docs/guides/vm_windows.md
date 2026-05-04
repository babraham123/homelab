# Windows VM setup
Guide to create a Windows VM. 

- First do the basic [VM setup](./vm.md)

## Images
- Download the Windows [ISO](https://www.microsoft.com/software-download/windows11)
- Download the Windows VirtIO [drivers](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)
- Upload ISOs to Proxmox on "local"

## Configure VM
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
		- username = `gaming\admin`, login password
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

## SSH
- Install SSH ([src](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell))
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
# Use powershell for the default shell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name "DefaultShell" -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
# Grant administrator access if available
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -PropertyType DWord -Force
```
- Shutdown VM

## GPU Passthrough
[src](https://3os.org/infrastructure/proxmox/gpu-passthrough/gpu-passthrough-to-vm/#proxmox-configuration-for-gpu-passthrough), [vid](https://www.youtube.com/watch?v=fgx3NMk6F54)
- Follow the steps in [Proxmox > PCI passthrough](./proxmox.md#pci-passthrough)
- Create VM, add PCI Device
- Install Geforce Experience
	- Open NVIDIA Control Panel, test 3D acceleration

## Automation
Create a mechanism to programmatic execute commands remotely. These commands are specific to the gaming VM but they can be generalized.
- Start the gaming VM
- Install the homelab source code
```bash
# From your local machine
tools/render_src.sh /tmp/homelab-rendered
tools/upload_src.sh gaming /tmp/homelab-rendered
ssh -l admin gaming
```
- Create autoadmin user, enable key based access
```powershell
# Create user
$Password = Read-Host -AsSecureString "Enter the new password"
New-LocalUser -Name "autoadmin" -Password $Password -FullName "autoadmin" -Description "low privilege user to remotely execute commands" -AccountNeverExpires -PasswordNeverExpires
# Install files
Copy-Item -Path "C:\Users\admin\gaming-src\autoadmin_sshd.conf" -Destination "C:\ProgramData\ssh\sshd_config.d"
icacls "C:\ProgramData\ssh\sshd_config.d\autoadmin_sshd.conf" /inheritance:r /grant "SYSTEM:(F)" /grant "Administrators:(F)"

$Path = "C:\Users\autoadmin\Dispatcher.ps1"
Copy-Item -Path "C:\Users\admin\gaming-src\Dispatcher.ps1" -Destination $Path
$Acl = Get-Acl -Path $Path
$Acl.SetOwner(New-Object System.Security.Principal.NTAccount("autoadmin"))
Set-Acl -Path $Path -AclObject $Acl

# Install dispatcher commands
C:\Users\admin\gaming-src\InstallAutomation.ps1
exit
```
