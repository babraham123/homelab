# Install a series of Scheduled Tasks on Windows 11. The Homelab_ tasks without a trigger
# correspond 1:1 with the ones listed in ./Dispatcher.ps1

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType Service -RunLevel Highest
$powershell = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$nvidiaSmi = "C:\Windows\System32\nvidia-smi.exe"
# 160 W, 80% of the RTX 3060 Ti's 200 W default: at 200 W it ran at 90°C with the fan at 100%,
# hit hardware thermal slowdown, and the driver hung. The limit resets at boot and when the
# driver recovers from a hang, so it's set at startup and again before each stream.
$gpuPowerLimit = "-pl 160"

# Add Scheduled Tasks

$action = New-ScheduledTaskAction -Execute $nvidiaSmi -Argument $gpuPowerLimit
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "Homelab_GpuPowerLimit" -Action $action -Trigger $trigger -Principal $principal -Force

$action = @(
    (New-ScheduledTaskAction -Execute $nvidiaSmi -Argument $gpuPowerLimit),
    (New-ScheduledTaskAction -Execute $powershell -Argument '-NoProfile -Command "Start-Service -Name SunshineService"')
)
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
