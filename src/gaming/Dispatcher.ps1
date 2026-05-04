# SSH Forced Command Dispatcher
# This script is triggered by the SSH daemon when the specific automation key is used.
# It parses $SSH_ORIGINAL_COMMAND to determine which action to take.
# Usage:
#   ssh autoadmin@gaming CMD
$OriginalCommand = $env:SSH_ORIGINAL_COMMAND
$SshClient = $env:SSH_CLIENT

Write-Host "Request received: '${OriginalCommand}' from ${SshClient}"

switch ($OriginalCommand) {
    "start_sunshine" {
        Start-ScheduledTask -TaskName "Homelab_StartSunshine"
    }
    "stop_sunshine" {
        Start-ScheduledTask -TaskName "Homelab_StopSunshine"
    }
    Default {
        Write-Error "Unauthorized command: '${OriginalCommand}'"
        exit 1
    }
}
Write-Host "Command completed"
