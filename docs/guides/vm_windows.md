# Windows VM setup
Guide to create a Windows VM. 

- First do the basic [VM setup](./vm.md)

## Images
- Download the Windows [ISO](https://www.microsoft.com/software-download/windows11)
- Download the Windows VirtIO [drivers](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)
- Upload ISOs to Proxmox on "local"

## Configure VM
[src](https://www.wundertech.net/how-to-install-windows-11-on-proxmox/), [tips](https://pve.proxmox.com/wiki/Windows_11_guest_best_practices), [vid](https://www.youtube.com/watch?v=fupuTkkKPDU)
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
  - On mac, verify connection
    - install `Windows App`, click Add PC
    - username = `gaming\admin`, login password
  - Disable login, [ref](https://answers.microsoft.com/en-us/windows/forum/all/how-to-login-automatically-to-windows-11/c0e9301e-392e-445a-a5cb-f44d00289715)
- Install apps
  - Enable copy-paste: win R, `rdpclip.exe`, enter
  - Launch shell: win R, `PowerShell`, ctrl shift enter
```powershell
winget install -e -h --accept-source-agreements --accept-package-agreements --id 7zip.7zip
winget install -e -h --accept-source-agreements --accept-package-agreements --id Adobe.Acrobat.Reader.64-bit
winget install -e -h --accept-source-agreements --accept-package-agreements --id Google.Chrome
winget install -e -h --accept-source-agreements --accept-package-agreements --id JanDeDobbeleer.OhMyPosh
winget install -e -h --accept-source-agreements --accept-package-agreements --id Microsoft.PowerToys
winget install -e -h --accept-source-agreements --accept-package-agreements --id Notepad++.Notepad++
winget install -e -h --accept-source-agreements --accept-package-agreements --id PuTTY.PuTTY
winget install -e -h --accept-source-agreements --accept-package-agreements --id GNU.Nano
winget install -e -h --accept-source-agreements --accept-package-agreements --id Valve.Steam
```

## SSH
- Install SSH, [src](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell)
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
# Enable access
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
# Use powershell for the default shell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name "DefaultShell" -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
# Grant administrator access if available
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -PropertyType DWord -Force
# Enable ping
Enable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In"
New-NetFirewallRule -DisplayName "Allow Inbound ICMPv4" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -Profile Any

# Code upload destination
New-Item -ItemType Directory -Path "C:\Homelab" -Force
icacls "C:\Homelab" /grant "admin:(OI)(CI)(F)"
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
ssh admin@gaming
```
- Create autoadmin user, enable key based access
```powershell
# Create user
$password = Read-Host -AsSecureString "Enter the new password"
New-LocalUser -Name "autoadmin" -Password $password -FullName "autoadmin" -Description "low privilege user to remotely execute commands" -AccountNeverExpires -PasswordNeverExpires
Add-LocalGroupMember -Group "Users" -Member "autoadmin"
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "autoadmin"
$cred = New-Object System.Management.Automation.PSCredential("autoadmin", $password)
Start-Process "cmd.exe" -Credential $cred -ArgumentList "/c exit" -LoadUserProfile

# Install drop folder and watcher script
New-Item -ItemType Directory -Path "C:\SSH_Triggers" -Force
icacls "C:\SSH_Triggers" /grant "autoadmin:(OI)(CI)(F)"
$powershell = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$action = New-ScheduledTaskAction -Execute $powershell -Argument "-NoProfile -WindowStyle Hidden -File C:\Homelab\gaming-src\WatchFolder.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 3650)
Register-ScheduledTask -TaskName "Homelab_Monitor_SSH_Drop" -Action $action -Trigger $trigger -Settings $settings -User "NT AUTHORITY\SYSTEM" -Force
Start-ScheduledTask -TaskName "Homelab_Monitor_SSH_Drop"

# Install config
$path = "C:\ProgramData\ssh\sshd_config"
(Get-Content "C:\Homelab\gaming-src\sshd_start.conf"), (Get-Content $path) | Set-Content $path
Add-Content -Path $path -Value (Get-Content "C:\Homelab\gaming-src\sshd_end.conf")
# Install dispatcher commands
powershell -ExecutionPolicy Bypass -File "C:\Homelab\gaming-src\InstallAutomation.ps1"
exit
```
- Generate the SSH certs
```
ssh manualadmin@pve1
sudo /root/homelab-rendered/src/certificates/ssh_cert_gen_windows.sh
```