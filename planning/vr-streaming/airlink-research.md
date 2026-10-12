# Air Link in the gaming VM: research

Research for 01 and 04, 2026-10-12. Primary sources first. Community reports are marked
(community); claims no source confirms are marked (unverified).

## Recommendation

1. **Resolve install paths; don't hardcode them.** Meta's current developer docs put the tools
   under `C:\Program Files\Meta Horizon\Support\...`. 01 and the gaming guide use
   `C:\Program Files\Oculus\Support\...`, which may only hold on installs that predate the rename
   (unverified). In 01, read the real path from the service first:
   `(Get-CimInstance Win32_Service -Filter "Name='OVRService'").PathName`. 02 should derive
   `OculusClient.exe` from the same root.
2. **Add a pairing step to 01, done over Moonlight, not RDP.** Pairing needs a click on
   **Confirm** in the PC app, which needs a desktop in the console session. Sunshine streams the
   console session, so pair once from the Mac with Moonlight, then `StopSunshine` and run the
   headless test. Whether pairing survives reboots is unverified; 01 should check that it does.
3. **Keep the scheduled task with an `Interactive` principal.** Microsoft documents that logon
   type as "run only in an existing interactive session", so it depends on autologon's console
   session. Before starting it, check `query session` shows `admin` on `console`. If an RDP session
   took it, `tscon <id> /dest:console` (run as admin) hands it back (community practice, see
   [RDP](#rdp-and-the-console-session)).
4. **Expect OVRService as installed to be enough; test the admin step anyway.** The service's
   launcher starts `OVRServer_x64.exe` in the active interactive session and logs "no active
   interactive user session" when there isn't one (community). The guide's "run `OVRServer_x64.exe`
   as admin" step looks like a workaround for a stopped service. Only the Debug Tool is documented
   as needing admin.
5. **No hypervisor hiding.** Nothing says Link refuses VMs. NVIDIA supports GeForce passthrough on
   R465+ drivers, and the Proxmox wiki says VM detection "should no longer be an issue" there. The
   maintainer already plays Rift games in this VM by hand, which is the best evidence. Don't add
   `kvm=off` / `hidden=1`.
6. **Keep the display output (dummy plug or TV) for 01's test.** Meta's requirements say nothing
   about a monitor. Treat "works with no output" as an optional extra test, not the baseline.
7. **Discovery and ports are undocumented; 01 must capture them.** Meta only says "same network".
   It publishes no service type, broadcast scheme or ports, so 04 can't write a rule in advance.
   The gaming guide already tells you to enable mDNS reflection for Air Link, so the bridge likely
   worked before. In 01, also capture UDP 5353 on WiFiTrusted during pairing (pfSense Diagnostics >
   Packet Capture). That shows whether discovery is mDNS, and under which service type.
8. **Set the VM's network profile to Private** if it is Public, and check that an inbound rule
   covers `OVRServer_x64.exe`. Meta says to rule out the firewall. On Meta's forum, several users
   found the PC "not discoverable" until they switched Public to Private, and others found
   OVRServer missing from the allowed apps (community). Virtual Desktop's FAQ gives the same
   advice. In 01, record the profile (`Get-NetConnectionProfile`) and whether
   `Get-NetFirewallApplicationFilter` lists OVRServer.
9. **04: set the bitrate in the headset, not the Debug Tool.** The in-headset Air Link bitrate tops
   out at 200 Mbps (community). A Meta employee reported that an ODT encode bitrate could drop Air
   Link to ~15 Mbps in a 2026 release (community, unverified). Meta says to zero the ODT numbers if
   Link misbehaves. Keep the ODT for the HUD and the codec switch.
10. **04's codec matrix is right, and AV1 is moot.** The ODT's codec choices are Default / H.264 /
    H.265. The 3060 Ti has no AV1 encoder (NVIDIA matrix), so a Quest 3 changes nothing.
11. **AP settings match Meta's advice; add DFS.** Meta says 5 GHz, 80 MHz locked, PC wired, same
    room, and warns that DFS channels can hurt Air Link. Pick a fixed non-DFS 80 MHz channel. The
    EAP660 HD is dual-band Wi-Fi 6 with no 6 GHz radio, so Quest 3's 6E doesn't apply.
12. **Virtual Desktop isn't a sure escape from cross-VLAN discovery.** The spec says it "connects
    by IP, so no mDNS". VD's FAQ documents no manual-IP entry and requires the headset on "the same
    network". VDXR is an OpenXR runtime; Rift games still need the Oculus runtime.

## Meta Horizon Link on Windows

| Item | Finding | Source |
|---|---|---|
| App name | "Meta Horizon Link" app (formerly Oculus app, then Meta Quest Link) | Meta help 509273027107091, 1517439565442928 |
| Tools path | `C:\Program Files\Meta Horizon\Support\oculus-diagnostics\` (ODT, log gatherer) | Meta dev docs (ODT, Unity Link) |
| Legacy path | `C:\Program Files\Oculus\Support\oculus-runtime\OVRServer_x64.exe` | gaming guide; third-party (unverified for new installs) |
| Service | `OVRService`, "Oculus VR Runtime Service"; launcher spawns `OVRServer_x64.exe` | community; ODT docs only say "the Oculus service" |
| Admin | ODT "requires administrator privilege"; nothing says the service or app needs admin | Meta ODT docs |
| App running | Pairing is confirmed in the PC app. Meta's troubleshooting page (as indexed) says to make sure the app is open; whether a connection works with only the service after pairing is **unverified** | Meta help 509273027107091, 975178886590868 |
| Air Link on | Automatic on current Horizon OS (Quick Settings > Link > Use Air Link) | Meta help 509273027107091 |

- **Pairing flow:** pick the PC on the headset, check that the code matches, click **Confirm** in
  the PC app, then **Launch** on the headset.
- **Settings reset:** Meta says to set all ODT numeric values to 0 and restart the app if Link
  misbehaves after changing the encode bitrate or resolution.

## VMs, headless GPUs and RDP

### VM detection

- **NVIDIA:** GeForce passthrough to a Windows VM is supported on R465 and later, one VM per GPU.
- **Proxmox wiki:** software refusing to run in a VM "should no longer be an issue with Nvidia
  drivers 465 and newer". It recommends q35 + OVMF and doesn't recommend hiding the hypervisor.
- **Meta:** the Link PC requirements don't mention VMs or monitors. Workstation cards, Intel Arc
  and some low-end GPUs are unsupported; the RTX 30 series is listed.
- **Community, Proxmox forum (2022–2023):** a Quest 2 user with an RTX 3080 VM and a dummy plug
  couldn't get Air Link working. Another got stuck on "Oculus isn't working properly". No root
  cause was found.
- **Community, Unraid forum (2020–2023):** wired Link in a VM worked once a whole USB controller
  was passed through. That doesn't apply to Air Link.
- **No source found** of Link detecting a hypervisor, or of `kvm=off` / `hidden=1` fixing Link.

### Headless GPU

- **No primary source** says whether Link needs a display attached to the GPU (**unverified**).
- **General:** dummy plugs exist because a GPU with no attached display may not bring up a
  desktop (XDA, vendor pages).
- **Here:** the VM keeps its Sunshine display output, so 01 tests with it attached.

### RDP and the console session

- **Sessions:** each RDP logon gets its own session ID. The console session is the one attached to
  the physical display (`WTSGetActiveConsoleSessionId`). On Windows client, connecting over RDP
  moves the user's session off the console, so a GPU-rendered app loses its display.
- **Sunshine (official repo, issue #964):** after an RDP disconnect, Moonlight can't connect to
  Sunshine's service until the session is moved back with `tscon`. That leaves the desktop
  unlocked.
- **tscon:** syntax is `tscon <sessionID> /dest:<sessionname>`. Microsoft's reference also says
  "You can't connect to the console session". In practice, `tscon <rdp-id> /dest:console` run as
  admin inside the RDP session is the widely used workaround (community: Login VSI, TestArchitect
  KBs).
- **Scheduled tasks:** `Interactive` logon (`TASK_LOGON_INTERACTIVE_TOKEN`) means "User must
  already be logged on. The task will be run only in an existing interactive session." With
  autologon and no RDP, that is the console session.

## Discovery, ports and VLANs

- **Meta:** headset and computer must be "connected to the same network"; Meta doesn't define it
  further. No Meta page lists ports, protocols, multicast or subnet requirements.
- **Discovery protocol:** **unverified.** A 2021 UniFi setup blog calls Air Link "a multicast
  protocol" and enables mDNS and IGMP snooping (community). It also says the PC must have only one
  IP on the adapter (community).
- **Ports:** **unverified.** No primary source. One unattributed troubleshooting page mentions TCP
  5669; it is too weak to use. 01's pfSense States capture is the only reliable source.
- **This network:**
  - The gaming guide already pairs Air Link with "Enable mDNS reflection" in the router guide, so
    discovery across VLAN 10 → pve2 likely worked before (unverified: the guide doesn't record
    which VLAN the headset was on).
  - WiFiTrusted copies LAN's rules (allow any), so routed unicast should pass without new rules.
- **pfSense mDNS bridge (mdns-bridge, Denny Page):**
  - Forwards mDNS between interfaces, IPv4 and IPv6.
  - Allow/deny filters by service label, global or per interface.
  - Never forwards link-local addresses.
  - It doesn't relay plain UDP broadcast. If Air Link discovery turns out to be broadcast, the
    bridge won't help (**unverified** which it is).
- **mDNS-bridge interfaces:** the router guide adds interfaces in two places. Install time picks
  "all the available interfaces", and later only WiFiTrusted is added. Check that PVE2 is in the
  list.
- **Bufferbloat limiters don't touch this path.** Netgate's CoDel recipe applies them through a
  floating rule on WAN, direction out. Inter-VLAN traffic isn't shaped (inference from the recipe).

## Bitrate, codecs and the HUD

### Oculus Debug Tool (Meta docs)

- **Path:** `Program Files\Meta Horizon\Support\oculus-diagnostics\OculusDebugTool.exe`. It needs
  admin.
- **Restart:** Link settings take effect after `OVRServer` restarts (menu: Restart Oculus Service).

| ODT setting | Values |
|---|---|
| Encode Bitrate (Mbps) | 1–2000; "high values can cause instability" |
| Encode Dynamic Bitrate | Default / Disabled / Enabled (adapts up to the target) |
| Dynamic Bitrate Max, Dynamic Bitrate Offset (Mbps) | integers; the offset overrides the max |
| Video Codec | Default / H.264 / H.265 (no AV1) |
| Encode Resolution Width | 0–15360 |
| Sliced Encoding, Link Sharpening, Distortion Curvature | toggles |
| Mobile ASW | "Enabled - Framerate Insurance" (AFI, Air Link, v38+, not at 120 Hz) |

- **Air Link bitrate (community):**
  - In-headset setting up to 200 Mbps.
  - Default reported as 100 Mbps.
  - A Meta employee on the forums said an ODT encode bitrate could drop Air Link to about
    15 Mbps until a fix shipped (**unverified**: thread not readable here).
- **Default codec over Air Link:** **unverified.**
- **Codecs:**
  - The 3060 Ti (GA104) encodes H.264 and HEVC; AV1 encode starts with RTX 40 (NVIDIA matrix).
  - The ODT exposes no AV1 option for Link at all.
  - Quest 3 AV1 decode is used by Virtual Desktop, not Link.
- **Refresh rate:** 72, 80, 90 or 120 Hz, set in the PC app's Graphics preferences (Meta).
- **ODT CLI (community):** `OculusDebugToolCLI.exe` beside the ODT runs commands from a text file
  (e.g. `service set-pixels-per-display-pixel-override 1.5`). It could set things over SSH without
  a desktop. Command names for HUD and bitrate are **unverified**.

### Performance HUD

- **Turn it on:** ODT > HUDs > Visible HUD = Performance, then pick a Mode. F11 cycles the modes.
- **Performance Summary (Meta docs):**
  - **Application Frames Dropped:** the app missed `ovr_EndFrame` for a frame.
  - **Compositor Frames Dropped:** the compositor missed V-Sync.
  - **App Motion-to-Photon Latency.**
  - **Performance headroom:** 1 − frame render time / V-Sync interval.
- **Oculus Link / Oculus Link Detail modes:** they exist in the ODT, but Meta doesn't document
  their fields (**unverified**). Record what they show, likely bitrate and encode/network timings.
- **Reading it for 04:** a rising compositor-dropped count with app headroom left points to the
  stream (network or encode), not the GPU.

### Wi-Fi

- **Meta's recommendations:**
  - 5 GHz, with the channel width locked to 80 MHz.
  - The PC wired to the router, so only the headset uses Wi-Fi.
  - Stay close to the router, "preferably into the same room with a clear line of sight".
  - Consider a dedicated router.
  - Minimize the devices between the computer and the headset.
- **Older Meta advice (2021):** an AC or AX router, PC on Ethernet, play space within about 20 ft
  of the router.
- **DFS (Meta):** "DFS channels may cause slower download speeds and affect applications that use
  your Wi-Fi network like Air Link."
- **EAP660 HD (vendor):**
  - 802.11ax, 2.4 and 5 GHz only.
  - Up to 2402 Mbps on 5 GHz, 2.5 GbE uplink.
  - Its spec doesn't say whether 160 MHz is supported.
- **Headsets:**
  - Quest 3 / 3S: Wi-Fi 6E (Meta). This AP has no 6 GHz, so 6E brings nothing here.
  - Quest 2: Meta's current comparison page omits it (**unverified**; usually quoted as Wi-Fi 6).

## Virtual Desktop as fallback

- **Network (VD FAQ):**
  - PC wired to a 5 GHz AC/AX router.
  - Headset on "the same network" (it warns about guest networks).
  - Windows firewall profile set to Private.
  - No VPN.
- **IP connections:** remote (internet) connections use UPnP or forwarded TCP 38810, 38820, 38830
  and 38840. The FAQ documents no manual-IP option on the LAN; how VD discovers PCs is
  **unverified**.
- **Games:** the FAQ says Oculus Rift games are supported on a VR-ready Windows PC, launched from
  VD's Games tab.
- **VDXR:**
  - VD's OpenXR runtime, an alternative to SteamVR for OpenXR games.
  - Choices: Automatic / SteamVR / VDXR; about 10% faster per the developer.
  - It doesn't replace the Oculus runtime for Rift-store (LibOVR) games (UploadVR, Khronos news).

## Sources

- **Meta help:**
  - Set up Link and Air Link: https://www.meta.com/help/quest/509273027107091/
  - Air Link Wi-Fi troubleshooting: https://www.meta.com/help/quest/2094726341404944/
  - Link troubleshooting (same network, firewall, ODT reset):
    https://www.meta.com/help/quest/975178886590868/
  - Getting started with the Meta Horizon Link app:
    https://www.meta.com/help/quest/1517439565442928/
  - Windows PC requirements: https://www.meta.com/help/quest/444256562873335/
  - D-Link VR Air Bridge (PC on Ethernet, shared-network congestion):
    https://www.meta.com/help/quest/2093693094163790/
  - DFS channels and Air Link: https://www.meta.com/help/quest/1164734251102834/
  - Air Link announcement (2021): https://www.meta.com/blog/introducing-oculus-air-link-a-wireless-way-to-play-pc-vr-games-on-oculus-quest-2-plus-infinite-office-updates-support-for-120-hz-on-quest-2-and-more/
  - Release notes (v28–v34): https://www.meta.com/en-gb/help/quest/3608590089449049/
- **Meta developer docs:**
  - Oculus Debug Tool: https://developers.meta.com/horizon/documentation/native/pc/dg-debug-tool/
  - Performance HUD: https://developers.meta.com/horizon/documentation/native/pc/dg-hud/
  - Link for Unity (diagnostics path):
    https://developers.meta.com/horizon/documentation/unity/unity-link
  - Air Link Framerate Insurance:
    https://developers.meta.com/horizon/blog/air-link-framerate-insurance-afi/
  - How Link works (H.264, HUD over Link):
    https://developers.meta.com/vr/blog/how-does-oculus-link-work-the-architecture-pipeline-and-aadt-explained/
  - Device comparison (Quest 3 / 3S Wi-Fi 6E):
    https://developers.meta.com/vr/resources/compare-devices/
- **NVIDIA:**
  - GeForce passthrough (R465+): https://nvidia.custhelp.com/app/answers/detail/a_id/5173
  - NVENC/NVDEC matrix: https://developer.nvidia.com/video-encode-decode-support-matrix
- **Proxmox:** PCI passthrough wiki: https://pve.proxmox.com/wiki/PCI_Passthrough
- **Microsoft:**
  - tscon: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/tscon
  - RDP sessions: https://learn.microsoft.com/en-us/windows/win32/termserv/terminal-services-sessions
  - Console session ID:
    https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-wtsgetactiveconsolesessionid
  - Task logon types: https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-logontype
  - New-ScheduledTaskPrincipal:
    https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal
- **Sunshine:** RDP disconnect and tscon: https://github.com/LizardByte/Sunshine/issues/964
- **pfSense:**
  - mdns-bridge: https://github.com/dennypage/mdns-bridge
  - CoDel limiters recipe: https://docs.netgate.com/pfsense/en/latest/recipes/codel-limiters.html
- **TP-Link:** EAP660 HD specs:
  https://www.omadanetworks.com/us/business-networking/omada-wifi-ceiling-mount/eap660-hd/
- **Virtual Desktop:**
  - FAQ: https://www.vrdesktop.net/
  - VDXR: https://www.uploadvr.com/virtual-desktops-vdxr-runtime/,
    https://www.khronos.org/news/permalink/virtual-desktops-new-openxr-runtime-bypasses-steamvr-to-boost-performance
- **Community:**
  - Proxmox forum, Air Link in a VM:
    https://forum.proxmox.com/threads/proxmox-for-vr-development.109991/
  - Unraid forum, Link in a VM:
    https://forums.unraid.net/topic/90618-oculus-quest-w-oculus-link-on-win-10-vm/
  - Steam forum, OVR launcher "no active interactive user session":
    https://steamcommunity.com/discussions/forum/11/1500126447393854379/
  - Meta forum, Air Link pairing fixed by Private profile; OVRServer missing from firewall:
    https://communityforums.atmeta.com/t5/Get-Help/My-PC-isn-t-showing-up-in-Air-Link/td-p/978145
  - Meta forum, Air Link bitrate and ODT (not readable here):
    https://communityforums.atmeta.com/discussions/PairingConnection/latest-update-ignores-airlink-bitrate-setting-completely/1365759
  - UniFi Air Link blog (multicast, single IP):
    https://techbloggingfool.com/2021/05/02/oculus-air-link-setup-on-unify-networks/
  - Air Link default bitrate 100 Mbps: https://vrpupu.com/en/2026/01/air-link-complete-guide/
  - ODT CLI script files:
    https://forums.flightsimulator.com/t/oculus-quest-2-settings-rtx3070-oc/360654/14
  - tscon to console: https://docs.loginvsi.com/knowledge-base/KB/using-tscon-to-move-a-session-from-rdp-to-the-cons
  - Headless GPUs and dummy plugs:
    https://www.xda-developers.com/this-hdmi-dummy-plug-solved-my-headless-server-gpu-problems/
- **Unverified:**
  - Air Link discovery protocol and ports.
  - Whether Link needs an attached display.
  - Whether the app must run after pairing.
  - Whether pairing survives a reboot.
  - The default Air Link codec.
  - The fields of the Oculus Link HUD modes.
  - ODT CLI command names.
  - The install root on this VM.
  - Quest 2's Wi-Fi standard.
  - How Virtual Desktop discovers PCs.
