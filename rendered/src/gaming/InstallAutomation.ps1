# Install a series of Scheduled Tasks on Windows 11. These tasks should correspond 1:1
# with the ones listed in ./Dispatcher.ps1

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType Service -RunLevel Highest
$powershell = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

# Add Scheduled Tasks

$action = New-ScheduledTaskAction -Execute $powershell -Argument '-NoProfile -Command "Start-Service -Name SunshineService"'
Register-ScheduledTask -TaskName "Homelab_StartSunshine" -Action $action -Principal $principal -Force

$action = New-ScheduledTaskAction -Execute $powershell -Argument '-NoProfile -Command "Stop-Service -Name SunshineService"'
Register-ScheduledTask -TaskName "Homelab_StopSunshine" -Action $action -Principal $principal -Force

# Install the dispatcher script
$dpath = "C:\Users\autoadmin\Dispatcher.ps1"
Copy-Item -Path "C:\Homelab\gaming-src\Dispatcher.ps1" -Destination $dpath
$acl = Get-Acl -Path $dpath
$user = [System.Security.Principal.NTAccount]"autoadmin"
$acl.SetOwner($user)
Set-Acl -Path $dpath -AclObject $acl

# Add a Task for running this script. Must be last
$action = New-ScheduledTaskAction -Execute $powershell -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\Homelab\gaming-src\InstallAutomation.ps1"
Register-ScheduledTask -TaskName "Homelab_InstallAutomation" -Action $action -Principal $principal -Force
