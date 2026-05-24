# A lightweight script that runs silently in the background, watches that folder,
# and fires up your dispatcher tasks when the correct file appears.

$triggerDir = "C:\SSH_Triggers"

while ($true) {
    # Find any files, check that they start with 'Homelab_'
    $files = Get-ChildItem -Path $triggerDir -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        if (-not $file.Name.StartsWith("Homelab_")) {
            Remove-Item $file.FullName -Force
            continue
        }

        # Run the task then delete the trigger
        Start-ScheduledTask -TaskName $file.Name
        Remove-Item $file.FullName -Force
    }

    Start-Sleep -Seconds 2
}
