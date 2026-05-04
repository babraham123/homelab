# Install a series of Scheduled Tasks on Windows 11. These tasks should correspond 1:1
# with the ones listed in ./Dispatcher.ps1

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType Service -RunLevel Highest
$powershell = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

$action = New-ScheduledTaskAction -Execute $powershell -Argument '-NoProfile -Command "Start-Service -Name Sunshine"'
Register-ScheduledTask -TaskName "Homelab_StartSunshine" -Action $action -Principal $principal

$action = New-ScheduledTaskAction -Execute $powershell -Argument '-NoProfile -Command "Stop-Service -Name Sunshine"'
Register-ScheduledTask -TaskName "Homelab_StopSunshine" -Action $action -Principal $principal
