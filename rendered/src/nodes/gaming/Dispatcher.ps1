# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@gaming CMD
$originalCommand = $env:SSH_ORIGINAL_COMMAND
$sshClient = $env:SSH_CLIENT

Add-Content -Path "$env:TEMP\dispatch.log" -Value "$originalCommand from $sshClient"
Write-Host "Request received: '${originalCommand}' from ${sshClient}"

$whitelist = @("StartSunshine", "StopSunshine", "InstallAutomation")
if ($originalCommand -notin $whitelist) {
    Write-Error "Unauthorized command: '${originalCommand}'"
    exit 1
}

# Prepend Homelab_ to $originalCommand and create a file with that name
New-Item -Path "C:\SSH_Triggers\Homelab_${originalCommand}" -ItemType File -Force | Out-Null

Write-Host "Command completed"
