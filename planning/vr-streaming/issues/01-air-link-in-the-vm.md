# 01. Prove Air Link works in the VM with no RDP session

Status: ready-for-human Type: prototype Repo: homelab Source: maintainer request 2026-10-12

## Question

Can a Quest connect over Air Link and play a Rift game when the VM was started headless, with
OVRService and the Link app started by a script and never through RDP? 02 automates the answer.

## Steps

- Start the VM with OliveTin's "Start Gaming Server", then stop Sunshine (`ssh autoadmin@gaming
  StopSunshine`).
- Over `ssh admin@gaming` only:
  - `Set-Service OVRService -StartupType Manual; Start-Service OVRService`.
  - Register a throwaway task with an interactive principal for the autologon user and start it.
    The task launches `C:\Program Files\Oculus\Support\oculus-client\OculusClient.exe`:
    `New-ScheduledTaskPrincipal -UserId admin -LogonType Interactive`.
- On the headset (WiFiTrusted, 5 GHz SSID), go to Quick Settings > Quest Link > Air Link and
  connect. Launch a Rift game.
- Stop by script: kill the client, `Stop-Service OVRService`, then `StartSunshine` and check that
  Moonlight still works.

## Record under ## Answer

- Does it work headless, or does the GPU need the display output it has for Sunshine (dummy plug or
  TV)?
- Is OVRService alone enough to accept a connection once paired, or must the Link app run?
- Does OVRService need to run as admin (as the guide's manual `OVRServer_x64.exe` step implies), or
  does the service work as installed?
- Ports and protocol: pfSense Diagnostics > States filtered on the headset IP during a session. 04
  needs these.
- Does the Windows network profile (Public or Private) block anything?
- Rough feel, plus the Oculus Debug Tool performance HUD: latency, dropped frames, bitrate.
- If Air Link fails, the reason. Then repeat with the Virtual Desktop Streamer before redesigning
  02.

## Comments
