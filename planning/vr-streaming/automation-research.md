# VR mode automation: scheduled tasks, Link, Sunshine, Playnite and OliveTin

Research for 02 and 03, 2026-10-12. (community) marks claims with no primary source, (unverified) claims
nobody has tested on the gaming VM, (est.) estimates. 01 confirms or corrects them.

## Recommendation

1. **The interactive-principal task works as 02 assumes.** SYSTEM can start any task. A task with
   `-LogonType Interactive` needs no password, and it runs only in the user's existing interactive
   session, so `admin` must already be logged on ([Scheduled tasks](#scheduled-tasks)).
2. **Use one mode script, not shared multi-action tasks.** Microsoft documents only that a task's
   actions run in order. That the next action waits for the previous one to exit, and runs even
   when it fails, is community-observed. A `Modes.ps1` in `gaming-src` keeps the tasks 1:1 with
   the triggers. It shares the stop steps as a PowerShell function, orders them for certain, and
   can wait for the autologon session. If 02 keeps action arrays, see
   [Reusing action objects](#reusing-action-objects).
3. **Stop by install path, not by process name.** The Link client is `OculusClient.exe` on older
   installs and `Client.exe` on newer ones, under `Program Files\Oculus` or `Program Files\Meta
   Horizon` (community). Kill whatever runs from `Support\oculus-client\`. Then stop OVRService,
   then kill any `OVRServer_x64` or `OVRRedir` left over.
4. **Re-apply `Set-Service OVRService -StartupType Manual` in `InstallAutomation.ps1`,** not just
   in the guide. Users report that a Link repair or some updates put it back to Automatic
   (community), and the `InstallAutomation` trigger can then fix it remotely.
5. **Register `Homelab_VRClient` with `-ExecutionTimeLimit ([TimeSpan]::Zero)`.** Its action is the
   Link client, so the task runs as long as the client does. The default limit is 72 hours, after
   which Task Scheduler ends it. The default `IgnoreNew` policy already stops a second `StartVR`
   from opening a second client.
6. **Stopping SunshineService is clean.** The service sends Sunshine a Ctrl-C. Sunshine then
   closes its running app (WM_CLOSE, and a kill after `exit-timeout`, 5 s by default), so `StartVR`
   also closes the flat-mode Playnite. Moonlight sees the stream drop.
7. **03 is fine as written.** `inlineAction` takes every action key, so `acls`, `timeout`,
   `maxConcurrent` and `id` are all valid there. The template already has a Jinja loop for "All
   Commands", so a loop over the start buttons matches the template's style. The ids become
   `main_start_gaming_tv` / `_vr`; nothing else refers to `main_start_gaming`.

Corrections for 06 (Playnite): `Playnite.DesktopApp.exe --startdesktop`, not plain
`Playnite.DesktopApp.exe`. Otherwise the "start in fullscreen" setting relaunches it as the
fullscreen app. `--shutdown` closes Playnite cleanly, but **only when run in admin's session**. Run
from SYSTEM it finds no instance and exits, so `StopVR` needs a second interactive task for it
([Playnite](#playnite)).

### Shape for 02

`src/nodes/gaming/Modes.ps1`, run by every mode task as SYSTEM:

```PowerShell
# The gaming VM's modes, one per scheduled task; see planning/vr-streaming/spec.md.
param([Parameter(Mandatory)][ValidateSet('StartSunshine', 'StopSunshine', 'StartVR', 'StopVR')]
      [string]$Mode)

function Stop-VR {
    # The client's exe name and install root changed across Link versions; its folder didn't
    Get-Process | Where-Object Path -like '*\Support\oculus-client\*' | Stop-Process -Force
    Stop-Service -Name OVRService -ErrorAction SilentlyContinue
    Stop-Process -Name OVRServer_x64, OVRRedir -Force -ErrorAction SilentlyContinue
}

# An interactive-token task fails unless admin is logged on; autologon can lag the boot
function Wait-AdminSession {
    for ($i = 0; $i -lt 30; $i++) {
        if (Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue |
            Where-Object UserName -like '*\admin') { return }
        Start-Sleep -Seconds 2
    }
    throw 'admin is not logged on'
}

switch ($Mode) {
    'StartSunshine' { Stop-VR; Start-Service -Name SunshineService }
    'StopSunshine'  { Stop-Service -Name SunshineService }
    'StartVR' {
        Stop-Service -Name SunshineService
        Start-Service -Name OVRService
        Wait-AdminSession
        Start-ScheduledTask -TaskName Homelab_VRClient
    }
    'StopVR' { Stop-VR }
}
```

`InstallAutomation.ps1`:

```PowerShell
foreach ($trigger in 'StartSunshine', 'StopSunshine', 'StartVR', 'StopVR') {
    $action = New-ScheduledTaskAction -Execute $powershell `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\Homelab\gaming-src\Modes.ps1 $trigger"
    Register-ScheduledTask -TaskName "Homelab_$trigger" -Action $action -Principal $principal -Force
}

# Starts the Link app in admin's console session; Homelab_StartVR runs it, the dispatcher can't
$action = New-ScheduledTaskAction -Execute "C:\Program Files\Oculus\Support\oculus-client\OculusClient.exe"
$user = New-ScheduledTaskPrincipal -UserId admin -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName Homelab_VRClient -Action $action -Principal $user -Settings $settings -Force

# Re-applied on every run: a Link repair or update can put it back to Automatic
Set-Service -Name OVRService -StartupType Manual
```

The client path comes from 01's answer. Use `-RunLevel Highest` only if 01 finds the Link app needs
admin; `Limited` (the default) gives admin's filtered token. Two different mode tasks can still
overlap (`StartVR` then `StartSunshine` within seconds). `MultipleInstances` only covers one task,
so the later task's `Stop-*` step decides the result.

### Shape for 03

```jinja
{%- for mode, trigger in [('TV', 'StartSunshine'), ('VR', 'StartVR')] %}
          - inlineAction:
              title: Start Gaming ({{ mode }})
              icon: <iconify-icon icon="maki:gaming"></iconify-icon>
              shell: ssh autoadmin@router start_pve2 && ssh autoadmin@pve2 start_gaming_vm && ssh autoadmin@gaming {{ trigger }}
              id: main_start_gaming_{{ mode | lower }}
              maxConcurrent: 1
              acls: [general]
              timeout: 120
{%- endfor %}
```

Check the whitespace in the rendered output (`tools/render_src.sh`). The button finishes once the
trigger file is dropped, not when Link is up, which is how the TV button already behaves. Optional:
an `actionGroups: {gaming: {maxConcurrent: 1}}` with `groups: [gaming]` on the start and stop
buttons would serialise them across buttons (3000.x; `latest-3k` is 3000.20.0). A press during a
run then queues (`queueSize` defaults to 5) instead of overlapping.

## Scheduled tasks

| Question | Answer | Source |
| --- | --- | --- |
| Can SYSTEM start a task whose principal is `admin`? | Yes: "Members of the Administrators group or the SYSTEM account can read, update, delete, and run any tasks." | MS: security contexts |
| Password needed for `-LogonType Interactive`? | No. A password is needed only for `TASK_LOGON_PASSWORD`, or for S4U as another user. | MS: security contexts, TASK_LOGON_TYPE |
| Which session, visible window? | `TASK_LOGON_INTERACTIVE_TOKEN`: "User must already be logged on. The task will be run only in an existing interactive session." It runs on admin's desktop, as "Run only when user is logged on" does in the UI. | MS: TASK_LOGON_TYPE |
| User not logged on? | The task doesn't run. The exact Last Run Result code is (unverified). | MS: TASK_LOGON_TYPE |
| `Start-ScheduledTask` blocking? | No, it "starts a registered background task asynchronously". | MS: Start-ScheduledTask |
| Multiple actions? | Up to 32, "executed sequentially". | MS: Task Actions, Register-ScheduledTask |
| Does action 2 wait for action 1 to exit? | Yes, "based upon observations, but this isn't documented anywhere" (community). | MS Q&A |
| Does a failing action stop the rest? | No: the next action runs "irrelevant of the first action's results" (community). An action whose exe is missing is (unverified). | MS Q&A |
| Can a task start another? | Yes: an action running `Start-ScheduledTask -TaskName X` (or `schtasks /Run /TN X`), since SYSTEM may run any task. | MS: security contexts |
| Second start while running? | Default `MultipleInstancesPolicy` is `IgnoreNew`: no new instance. | MS: MultipleInstancesPolicy |
| Long-running action? | Default `ExecutionTimeLimit` is three days; `PT0S` (`[TimeSpan]::Zero`) means no limit. | MS: New-ScheduledTaskSettingsSet, ExecutionTimeLimit |

`powershell.exe -Command` exits 1 when its last command fails. Task Scheduler records that as the
Last Run Result but doesn't act on it, so errors in a multi-action task are silent. A `-File` script
can `throw` and log.

Registering the interactive task from `InstallAutomation.ps1` (SYSTEM) needs no credentials, as the
`Homelab_*` SYSTEM tasks show today. That SYSTEM can register a task for another user without a
password is (unverified) on this VM; the doc describes registering from an Administrators member.

### Reusing action objects

`New-ScheduledTaskAction` returns a CimInstance (`MSFT_TaskExecAction`). `Register-ScheduledTask`
copies it into the task's XML, so one object can go into any number of tasks. Gotchas, if 02 keeps
action arrays:

- `$stop + $start` fails when `$stop` holds a single action: `+` on a CimInstance has no
  `op_Addition`. Build arrays with `@(...)`: `-Action (@($stopVR) + @($startOVR, $startClient))`.
- 32 actions per task at most.
- Each action is a fresh `powershell.exe` (about 0.5 s each, est.). With quoting nested inside
  `-Argument`, this reads worse than one `-File` script.
- `-Force` overwrites the task, so re-running `InstallAutomation` stays idempotent.

## Meta Horizon Link

No Meta document covers process or service names. Everything below is (community) unless marked.

| Item | Name | Note |
| --- | --- | --- |
| Service | `OVRService` ("Oculus VR Runtime Service") | Binary `OVRServiceLauncher.exe`; killing it needs admin |
| Runtime | `OVRServer_x64.exe`, `OVRRedir.exe` | Under `Support\oculus-runtime\`, started by the service |
| Link app | `OculusClient.exe` (older) or `Client.exe` (v83 era) | Under `Support\oculus-client\`, in `C:\Program Files\Oculus` or `C:\Program Files\Meta Horizon` |
| Old library service | `OVRLibraryService` | Present on some installs; v81 users report it can be ignored |

- **Does `Stop-Service OVRService` close the client?** No source says it does. When the service
  is down, the client stays open and shows "Can't reach the Oculus Runtime Service" (the 2018
  certificate outage). Kill the client first, so it doesn't sit on that error or retry the
  service, then stop the service. Oculus Killer, a community tool, ends `OVRServiceLauncher`,
  `OVRRedir` and `OVRServer_x64` with Ctrl-C signals, in that order.
- **Clean client close:** none is known. A SYSTEM task can't send WM_CLOSE to a window in admin's
  session (separate sessions), so `Stop-Process -Force` is the practical stop. Community tools do
  the same. Whether a hard kill loses state is (unverified).
- **OVRService on Manual:** users run it that way. One forum user says a Link repair or driver
  reinstall, and some updates, put it back to Automatic. A Meta community manager suggested
  "Automatic (Delayed Start)" for a different start-up problem. Nothing official on whether
  updates reset it, so re-apply the setting in `InstallAutomation.ps1` and check it in the
  acceptance test after a Link update.
- The guide's manual `OVRServer_x64.exe` run-as-admin step suggests the service didn't start the
  runtime in this VM at some point. 01 settles whether the service alone is enough.

## Sunshine

From the Sunshine source (`tools/sunshinesvc.cpp`, `src/process.cpp`,
`src/platform/windows/misc.cpp`, `src/stream.cpp`, `src/nvhttp.cpp`):

- **Service:** `SunshineService` (`sunshinesvc.exe`). It waits for an active console session, then
  starts `Sunshine.exe` in it with a copy of its SYSTEM token, inside a kill-on-close job object.
- **Stopping the service:** it sends `Sunshine.exe` a Ctrl-C through a helper and waits 20 s, then
  calls `TerminateProcess`. On Ctrl-C, Sunshine shuts down (forced after 10 s), and its process
  cleanup calls `proc.terminate()` on the running app. Stopping mid-stream is clean on the server;
  Moonlight sees a disconnect.
- **How apps start:** when Sunshine runs as SYSTEM, it launches the app with the console user's
  token (`WTSQueryUserToken`), elevated only if the app is marked so. The app runs in admin's
  session and is visible. With no console session, the launch fails.
- **Does the app stop when the stream ends?** Not on disconnect: when the last client leaves, a
  running app is left running (the tray shows "pausing"). The app is terminated when the client
  quits it (`/cancel`) or when Sunshine shuts down. A launch while an app runs is refused
  ("An app is already running on this host").
- **Termination:** WM_CLOSE to every window of the app's process group, then a forced kill after
  `exit-timeout` ("If unset, the default is to wait up to 5 seconds"). `auto-detach` and `wait-all`
  both default to true.
- Consequence for 06: if Playnite desktop is running (UEVR mode) and Moonlight then launches
  `Playnite.FullscreenApp.exe`, the new process switches the running instance to fullscreen and
  exits. Sunshine's `auto-detach` treats that as a launcher and keeps streaming. `StopVR` closing
  Playnite avoids the case.

## Playnite

From `source/Playnite/App/CmdLineOptions.cs` and `PlayniteApplication.cs`, and the manual:

| Option | Effect |
| --- | --- |
| `--hidesplashscreen` | No splash screen |
| `--startdesktop` | Start in desktop mode; switches a running fullscreen instance to desktop |
| `--startfullscreen` | The reverse |
| `--start <gameId>` (`--actionindex n`) | Start a game by library GUID, optionally a given play action |
| `--nolibupdate` | Skip the library update on start |
| `--shutdown` | Quit the running instance (saves settings and releases resources) |

- Playnite allows one instance. A second invocation finds the mutex `PlayniteInstaceMutex`, sends
  its command over a named pipe to the running instance, and exits.
- Started as `Playnite.DesktopApp.exe` with the "start in fullscreen" setting on and no
  `--startdesktop`, it relaunches as the fullscreen app. 06 should pass `--startdesktop`.
- **`--shutdown` from SYSTEM does nothing.** The mutex name has no `Global\` prefix, so it lives
  in admin's session namespace. A session-0 process doesn't see it, takes the "no instance" path,
  and exits at once. Run `Playnite.DesktopApp.exe --shutdown` from a second interactive task
  (e.g. `Homelab_VRClientStop`), started by `StopVR`. `Stop-Process` is the fallback; whether a
  hard kill can corrupt the LiteDB library is (unverified).
- Closing the main window doesn't quit by default: `CloseToTray` and `EnableTray` default to
  true. So `CloseMainWindow()` isn't a clean stop either.

## OliveTin

- `inlineAction` exists from 3000.7.0. In the source it is `*Action`, the same struct as a
  top-level action, so `id`, `acls`, `timeout`, `maxConcurrent`, `groups` and the rest all apply.
  The docs page shows only `title`, `shell` and `icon`.
- `timeout`: the default is 3 s, and the action is killed when it runs out. The TV button's 120
  stays right for VR, since the gaming hop returns as soon as the trigger file is dropped.
- `maxConcurrent: 1` blocks a second run of the same action. `actionGroups` (released in
  3000.20.0) share one limit across several actions.
- `acls: [general]` matches the `accessControlLists` entry in the template; `admins` reach every
  action through `addToEveryAction`.

## Sources

- **Task Scheduler (Microsoft Learn):**
  - Security contexts (who can run tasks, passwords):
    <https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks>
  - Logon types:
    <https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_logon_type>
  - Actions run sequentially, 32 max:
    <https://learn.microsoft.com/en-us/windows/win32/taskschd/task-actions>
  - `MultipleInstancesPolicy` default:
    <https://learn.microsoft.com/en-us/windows/win32/taskschd/taskschedulerschema-multipleinstancespolicy-settingstype-element>
  - `ExecutionTimeLimit` (`PT0S`):
    <https://learn.microsoft.com/en-us/windows/win32/taskschd/taskschedulerschema-executiontimelimit-settingstype-element>
  - Cmdlets:
    <https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal>,
    <https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask>,
    <https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/start-scheduledtask>,
    <https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset>
  - `-Command` exit codes:
    <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe>
  - Session namespaces for named objects:
    <https://learn.microsoft.com/en-us/windows/win32/termserv/kernel-object-namespaces>
  - (community) Action ordering and failure:
    <https://learn.microsoft.com/en-us/answers/questions/1634383/batch-job2-automatically-runs-upon-the-completion>
- **Meta Horizon Link (all community):**
  - Oculus Killer process list and order: <https://github.com/sulliops/OculusKiller>
  - Library and runtime services on Manual: <https://github.com/MattJaccino/ovrtoggle>
  - Client exe name and install path:
    <https://communityforums.atmeta.com/discussions/OtherTroubleshooting/oculus-link-not-working---oculusclient-exe-not-found-error/1362447>,
    <https://communityforums.atmeta.com/discussions/OtherTroubleshooting/meta-quest-link--installation-not-installing-files-and-drivers-correctly-/1355957>
  - Manual startup reset by repair or updates:
    <https://communityforums.atmeta.com/discussions/OtherTroubleshooting/how-to-stop-oculus-from-running-on-launch/1375805>
  - Delayed start and `OVRLibraryService`:
    <https://communityforums.atmeta.com/discussions/PairingConnection/pc-link-broken-with-update-v81/1348553>
  - "Can't reach the Oculus Runtime Service":
    <https://www.tomsguide.com/us/oculus-rift-expired-certificate-not-working,news-26733.html>
  - The forum pages returned 403 to direct fetches, so their wording comes from search excerpts.
- **Sunshine** (LizardByte/Sunshine, `master`, 2026-10-12):
  - Service wrapper: <https://github.com/LizardByte/Sunshine/blob/master/tools/sunshinesvc.cpp>
  - App lifecycle: <https://github.com/LizardByte/Sunshine/blob/master/src/process.cpp>
  - User-token launch and WM_CLOSE:
    <https://github.com/LizardByte/Sunshine/blob/master/src/platform/windows/misc.cpp>
  - Disconnect and `/cancel`: <https://github.com/LizardByte/Sunshine/blob/master/src/stream.cpp>,
    <https://github.com/LizardByte/Sunshine/blob/master/src/nvhttp.cpp>
  - App field descriptions:
    <https://github.com/LizardByte/Sunshine/blob/master/src_assets/common/assets/web/public/assets/locale/en.json>
  - Docs: <https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2app__examples.html>
- **Playnite:**
  - Manual: <https://api.playnite.link/docs/manual/advanced/cmdlineArguments.html>
  - Options:
    <https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/App/CmdLineOptions.cs>
  - Instance and pipe handling:
    <https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/App/PlayniteApplication.cs>
  - Tray defaults:
    <https://github.com/JosefNemec/Playnite/blob/master/source/Playnite/Settings/PlayniteSettings.cs>
- **OliveTin:**
  - Inline actions: <https://docs.olivetin.app/dashboards/inline-actions.html>
  - Concurrency and groups: <https://docs.olivetin.app/action_customization/concurrency.html>
  - Timeouts: <https://docs.olivetin.app/action_customization/timeouts.html>
  - Config structs at the latest release:
    <https://github.com/OliveTin/OliveTin/blob/3000.20.0/service/internal/config/config.go>
  - Group limits:
    <https://github.com/OliveTin/OliveTin/blob/3000.20.0/service/internal/executor/group_concurrency.go>
- **Unverified on the VM:**
  - The Last Run Result when admin isn't logged on.
  - Whether an action whose exe is missing stops later actions.
  - Registering an interactive task for admin from SYSTEM with no password.
  - Whether a hard kill of the Link client or Playnite loses state.
  - Whether OVRService alone starts the runtime here (the guide's manual step suggests not).
