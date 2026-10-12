# VR modes: hands-on investigation

One session at the VM and headset that settles what the research couldn't: 01 (parts 1–5), 04
(part 6) and 05 (part 7). Each part ends with **Record**: write it under `## Answer` in that
ticket, then set the ticket to `Status: resolved`. Background and sources are in
[airlink-research.md](airlink-research.md), [automation-research.md](automation-research.md) and
[uevr-research.md](uevr-research.md).

Everything here is throwaway: test tasks are named `Test_*` and part 8 removes them. 02 and 06
build the real automation from the answers.

## Before you start

- The Mac with Moonlight, the headset (charged, on the WiFiTrusted 5 GHz SSID), and its IP (pfSense
  Status > DHCP Leases).
- pfSense and pve1's Proxmox UI, and the Omada controller for the AP.
- One Rift-store game installed in the Link app. For part 7, one single-player Unreal Engine game
  with no anti-cheat (UE4/UE5, in Playnite).
- Start the VM with OliveTin's "Start Gaming Server". PowerShell commands run in `ssh admin@gaming`
  (an elevated shell) unless a step says Moonlight or headset.
- Never RDP into the VM during the session: it takes the console session off the GPU.

## 1. Facts on the VM

```powershell
$svc = Get-CimInstance Win32_Service -Filter "Name='OVRService'"
$svc | Select-Object State, StartMode, PathName
# The install root is everything before \Support\
$root = $svc.PathName -replace '^"?(.*?)\\Support\\.*$', '$1'
$root
Get-ChildItem "$root\Support\oculus-client" -Filter *.exe | Select-Object FullName
Get-ChildItem "$root\Support\oculus-runtime" -Filter '*openxr*.json' | Select-Object FullName
Get-ItemProperty HKLM:\SOFTWARE\Khronos\OpenXR\1 -Name ActiveRuntime -ErrorAction SilentlyContinue
Get-NetConnectionProfile | Select-Object InterfaceAlias, NetworkCategory
Get-NetFirewallApplicationFilter | Where-Object Program -like '*OVRServer*' |
    Get-NetFirewallRule | Select-Object DisplayName, Enabled, Direction, Action, Profile
query session
# The mode design assumes this; the reboot in part 4 checks it sticks
Set-Service OVRService -StartupType Manual
```

The client is the GUI exe in `oculus-client` (`OculusClient.exe` or `Client.exe`). Keep `$root`
and the client path for the later parts; a new `ssh` session needs them set again.

**Record (01):** install root, client path, OpenXR manifest path, network profile, any OVRServer
firewall rule, and that `query session` shows `admin` on `console`.

## 2. Pairing over Moonlight, with a discovery capture

1. pfSense > Diagnostics > Packet Capture: interface **WiFiTrusted**, protocol UDP, host = the
   headset's IP, count 0. Start it. Start a second capture on the **PVE2** interface the same way,
   in another tab, to see what the mDNS bridge relays.
2. Moonlight on the Mac > the gaming VM > Desktop.
3. In the Link app: sign in to the Meta account if asked. Settings > General > OpenXR Runtime >
   "Set Meta Horizon Link as active" (part 7 needs it).
4. Optional, for the HUD in parts 3 and 6: open
   `$root\Support\oculus-diagnostics\OculusDebugTool.exe` (needs admin), set Visible HUD =
   Performance, Mode = Performance Summary. Note whether it survives part 3's service restart.
5. Headset: Quick Settings > Link (Air Link) > pick the PC. Check the code, click **Confirm** in the
   Link app over Moonlight. Don't launch Link yet; disconnect.
6. If the headset doesn't list the PC:
   - set the profile to Private:
     `Set-NetConnectionProfile -InterfaceAlias <alias> -NetworkCategory Private`;
   - if part 1 found no OVRServer rule:
     `New-NetFirewallRule -DisplayName 'Meta Horizon Link' -Direction Inbound -Action Allow
     -Program "$root\Support\oculus-runtime\OVRServer_x64.exe" -Profile Private`;
   - retry, and note which change fixed it.
7. Stop both captures, download them, open them in Wireshark. Look for mDNS (UDP 5353, `_*._tcp`
   or `_*._udp` service names) and for broadcasts to `192.168.10.255` or `255.255.255.255`.

**Record (01):** discovery protocol and service type; whether the PVE2 capture shows it relayed;
what (if anything) had to change in the firewall or profile.

## 3. A scripted start, no desktop

Leave Moonlight, then from the Mac: `ssh autoadmin@gaming StopSunshine`. In `ssh admin@gaming`:

1. Start the runtime from the service and see where it runs:

   ```powershell
   Start-Service OVRService
   Start-Sleep 5
   Get-Process OVRServer_x64 -IncludeUserName | Select-Object Id, SessionId, UserName
   ```

2. Register the client task the way `InstallAutomation.ps1` will: from a SYSTEM task, with no
   password. Then SYSTEM starts it, as `WatchFolder.ps1` will.

   ```powershell
   $client = '<client path from part 1>'
   @"
   Register-ScheduledTask -TaskName Test_VRClient -Force -Action (New-ScheduledTaskAction -Execute '$client') -Principal (New-ScheduledTaskPrincipal -UserId admin -LogonType Interactive) -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero))
   Start-ScheduledTask -TaskName Test_VRClient
   "@ | Set-Content C:\Homelab\test_register.ps1
   Register-ScheduledTask -TaskName Test_AsSystem -Force `
       -Action (New-ScheduledTaskAction -Execute powershell.exe `
           -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Homelab\test_register.ps1') `
       -Principal (New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest)
   Start-ScheduledTask Test_AsSystem
   Start-Sleep 10
   (Get-ScheduledTaskInfo Test_AsSystem).LastTaskResult
   Get-Process | Where-Object Path -like '*\Support\oculus-client\*' |
       Select-Object Name, Id, SessionId
   ```

   The client should be in admin's console session (the `SessionId` from part 1's `query session`).
3. Headset: Quick Settings > Link > the PC > Launch. Start the Rift game and play a few minutes.
4. During play, pfSense > Diagnostics > States, filtered on the headset's IP.
5. With only the service: quit the game, disconnect the headset, then kill the client:
   `Get-Process | Where-Object Path -like '*\Support\oculus-client\*' | Stop-Process -Force`.
   Reconnect from the headset.
6. Only if steps 1–3 failed: try the guide's old way, the runtime as admin in admin's session:

   ```powershell
   Register-ScheduledTask -TaskName Test_OVRServer -Force `
       -Action (New-ScheduledTaskAction -Execute "$root\Support\oculus-runtime\OVRServer_x64.exe") `
       -Principal (New-ScheduledTaskPrincipal -UserId admin -LogonType Interactive -RunLevel Highest)
   Start-ScheduledTask Test_OVRServer
   ```

7. Optional: shut the VM down, remove the dummy plug (or unplug the TV), start it, and repeat 1–3.

**Record (01):** where `OVRServer_x64` runs (session, user); `Test_AsSystem`'s result and whether
the client came up in the console session; whether it played, with the HUD numbers and feel; the
protocols and ports in States; whether a connection works with only the service (step 5); whether
step 6 was needed; the optional no-display result.

## 4. Logged off, then a reboot

1. Log the console session off, then try the client task:

   ```powershell
   logoff <admin's console session ID from query session>
   Start-ScheduledTask Test_VRClient
   Start-Sleep 5
   Get-ScheduledTaskInfo Test_VRClient | Select-Object LastRunTime, LastTaskResult
   ```

2. `Restart-Computer`. Once it pings again, `ssh admin@gaming` and check how long autologon takes
   and what is running:

   ```powershell
   query session
   Get-Service OVRService | Select-Object Status, StartType
   ```

3. `Start-Service OVRService; Start-ScheduledTask Test_VRClient`, then connect from the headset
   without pairing again.

**Record (01):** the Last Run Result with admin logged off; the boot-to-autologon time; that
OVRService came up stopped and Manual; whether pairing survived the reboot.

## 5. Stop and switch back

```powershell
Get-Process | Where-Object Path -like '*\Support\oculus-client\*' | Stop-Process -Force
Stop-Service OVRService
Get-Process OVRServer_x64, OVRRedir, OVRServiceLauncher -ErrorAction SilentlyContinue
```

Then `ssh autoadmin@gaming StartSunshine` from the Mac and connect with Moonlight. On the desktop,
check the Link app for an error or repair prompt left by the hard kill.

**Record (01):** what survived `Stop-Service`; whether Moonlight connects; any error after the
kill.

## 6. Network path and quality (04)

1. pfSense > Services > mDNS Bridge: check that both **PVE2** and **WiFiTrusted** are selected.
2. Omada controller: note the 5 GHz radio's current channel and width, then set a fixed non-DFS
   channel (36–48 or 149–161) at 80 MHz.
3. Start VR: `Start-Service OVRService; Start-ScheduledTask Test_VRClient`, then connect. In the
   Oculus Debug Tool, set every numeric field to 0. The codec stays Default for the first runs.
4. Play the same scene for about 5 minutes per run. Set the bitrate in the headset's Air Link
   settings, not in the ODT. Watch pve1's Proxmox UI > the pfSense VM > Summary for CPU.

   | Run | Bitrate | Codec | App frames dropped | Compositor frames dropped | pfSense CPU | Feel |
   |---|---|---|---|---|---|---|
   | 1 | default | Default | | | | |
   | 2 | 200 Mbps | Default | | | | |
   | 3 | best so far | H.264 | | | | |
   | 4 | best so far | H.265 | | | | |

   Changing the codec in the ODT takes a service restart (ODT > Restart Oculus Service), so
   reconnect after it. Also note what the ODT's Oculus Link HUD modes show.
5. Play 20 minutes at the best setting.

**Record (04):** the table, the channel and width before and after, the mDNS bridge interfaces, the
20-minute result, and the chosen bitrate and codec.

## 7. UEVR (05)

1. Over Moonlight (`StartSunshine` if needed):
   - in `ssh admin@gaming`:

     ```powershell
     winget install -e -h --id Microsoft.DotNet.DesktopRuntime.6
     New-Item -ItemType Directory C:\UEVR -Force
     Add-MpPreference -ExclusionPath C:\UEVR
     ```

   - download the newest `UEVR.zip` from <https://github.com/praydog/UEVR-nightly/releases> and
     extract it into `C:\UEVR`;
   - run `C:\UEVR\UEVRInjector.exe`, select **OpenXR**, close the window (the choice is saved on
     close);
   - in Playnite, tag the test game `UEVR`;
   - in Playnite, Settings > Scripts > "Execute after a game is started", paste:

     ```powershell
     if ($Game.Tags.Name -contains 'UEVR') {
         $exe = (Get-ChildItem $Game.InstallDirectory -Recurse -Filter '*-Win64-Shipping.exe' |
             Select-Object -First 1).Name
         Get-Process UEVRInjector -ErrorAction SilentlyContinue | Stop-Process -Force
         Start-Process 'C:\UEVR\UEVRInjector.exe' -ArgumentList "--attach=$exe"
     }
     ```

2. Check the runtime: `(Get-ItemProperty HKLM:\SOFTWARE\Khronos\OpenXR\1).ActiveRuntime` should
   name the Oculus manifest from part 1.
3. Go to VR: `ssh autoadmin@gaming StopSunshine`, then
   `Start-Service OVRService; Start-ScheduledTask Test_VRClient`. Connect from the headset and open
   the Link desktop view.
4. In the desktop view, start Playnite (desktop mode) and launch the test game. Watch for the
   injector window, a UAC prompt, and whether the game appears in VR.
5. Controllers: try the Touch controllers with the desktop view open, then close it and try again.
6. If injection breaks the game at the splash screen, add a delay: replace the `Start-Process` line
   with the one below, at 3 s, then 10 s.

   ```powershell
   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command',
       "Start-Sleep 3; Start-Process 'C:\UEVR\UEVRInjector.exe' '--attach=$exe'"
   ```

7. In the UEVR menu (Insert, or L3+R3): Native Stereo, depth passed to the runtime
   (`VR_PassDepthToRuntime=true`), then lower `OpenXR_ResolutionScale` and in-game settings until
   the HUD shows no app frames dropped. Try Synchronized Sequential only if Native Stereo glitches.
8. Quit the game, then check `Get-Process UEVRInjector` and
   `Get-ChildItem $env:APPDATA\UnrealVRMod`.

**Record (05):** the nightly build and the game; whether `--attach` injected with no clicks, and at
which delay; any UAC prompt; the `ActiveRuntime` value; controllers with and without the desktop
view; the rendering settings and HUD numbers; whether `UEVRInjector` outlived the game; the profile
folder name.

## 8. Clean up

```powershell
Unregister-ScheduledTask -TaskName Test_VRClient, Test_AsSystem -Confirm:$false
Unregister-ScheduledTask -TaskName Test_OVRServer -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item C:\Homelab\test_register.ps1
```

- In Playnite, clear the temporary global script; 06 installs the real one. Keep the `UEVR` tag,
  `C:\UEVR` and the pairing.
- Put the AP back if part 6's channel didn't help.
- Stop with OliveTin's "Stop Gaming Server".
