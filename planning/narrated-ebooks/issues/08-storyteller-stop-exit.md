# 08. storyteller.service lands in failed after every stop

Status: ready-for-human
Type: task
Repo: homelab
Source: log sweep 2026-10-28

## Problem

Every stop of the storyteller container (image update, reinstall, reboot) ends with

```text
[FATAL tini (1)] Unexpected error when forwarding signal: 'Permission denied'
```

tini exits 1, podman reports the container as failed, and `storyteller.service` sits in `failed`
until something starts it again. Each stop raises `SystemdUnitFailed` for nothing, and a real
failure of the unit looks the same. Four times in the week of 2026-10-22.

The quadlet starts the container as `User=1000` so the image's entrypoint skips gosu. tini still
runs as PID 1 and gets EPERM on `kill()` of its child, so the child isn't the same uid or tini
isn't its parent the way it expects. The image is a local build of
`storyteller-platform/storyteller:web-v2`.

## Change

Find why the signal is refused (`podman exec storyteller ps -o pid,user,comm` while it runs; the
image's entrypoint and Dockerfile) and make the stop clean: run the server without tini through
`Exec=`, or fix the uid the child runs as. Confirm with `systemctl restart storyteller` leaving the
unit `inactive`, not `failed`, and no tini line in `podman logs storyteller`.

## Comments

- 2026-11-01: still true. tini logged the `Permission denied` FATAL on every stop through 2026-11-01
  05:11Z (six stops since 10-31). All of them came with a VM shutdown or reboot, so the unit never
  sat in `failed` and `SystemdUnitFailed` did not fire for storyteller in the last 5 days. A
  `systemctl restart storyteller` with the VM up would still leave it failed.
- 2026-11-01 agent: diagnosed from source and logs, fixed in the quadlet, not yet applied to
  websvcs.
  - Root cause: AppArmor, not a uid mismatch. tini prints `strerror(errno)`, and
    `Permission denied` is `EACCES`. The kernel's uid check for `kill()` fails with `EPERM`
    (`Operation not permitted`), which is what tini prints when uids differ or `CAP_KILL` is
    missing. `EACCES` comes from a security module, and on Debian that is AppArmor. Podman
    confines containers with its `containers-default-<version>` profile, which allows signals
    between processes only when the peer label equals that profile. With crun under its own
    AppArmor profile, container processes are labelled `containers-default-<version>//&crun`, a
    stack that this rule doesn't match. Signals from podman and crun into the container are still
    allowed, which is why tini gets the SIGTERM at all.
  - Evidence:
    - The uid is already the same. Started as 1000 with `FORCE_USER_SETTING`, the entrypoint runs
      `exec tini -- "$@"` without gosu
      ([entrypoint.sh L10-L20](https://gitlab.com/storyteller-platform/storyteller/-/blob/web-v2.14.23/docker-scripts/entrypoint.sh#L10-20)),
      so tini and node are both 1000. The setup line `FORCE_USER_SETTING is detected` is in every
      start's log. tini doesn't use `-g`, and `TINI_KILL_PROCESS_GROUP` isn't set, so it signals
      only node.
    - tini fails on the `kill()` itself and exits 1
      ([tini.c L526-L531](https://github.com/krallin/tini/blob/v0.19.0/src/tini.c#L526-L531)).
      Node never gets SIGTERM; it dies with the container when PID 1 exits.
    - The rules: `signal (send,receive) peer={{.Name}}` for processes in the container, and
      receive rules for `unconfined`, crun, runc and podman
      ([template L21-L27](https://github.com/containers/common/blob/79321a462b6ace6868caca2fb6b15f5b3c3fccfe/pkg/apparmor/apparmor_linux_template.go#L21-L27)).
    - The same symptom on another Podman host, with the kernel's line:
      `apparmor="DENIED" operation="signal" profile="containers-default-0.66.0" comm="tini"
      requested_mask="send" signal=term peer="containers-default-0.66.0//&crun"`
      ([sindredg/ai-security-platform#191](https://github.com/sindredg/ai-security-platform/issues/191)).
      Background on the crun and runc profiles that AppArmor 4 added:
      [LP#2040483](https://bugs.launchpad.net/ubuntu/+source/libpod/+bug/2040483).
    - VictoriaLogs: 11 tini lines between 2026-10-27 and 2026-11-01, all on websvcs and all from
      storyteller. No other container there forwards signals through an init. Kernel and audit
      lines aren't shipped, so the AppArmor denial itself isn't in VictoriaLogs.
  - Fix: `Entrypoint=node` and `Exec=--enable-source-maps server.js` (the image's `CMD`,
    [Dockerfile L147-L154](https://gitlab.com/storyteller-platform/storyteller/-/blob/web-v2.14.23/Dockerfile#L147-154)),
    with `FORCE_USER_SETTING` dropped because the entrypoint no longer runs. Node is PID 1 and gets
    podman's SIGTERM directly, which AppArmor allows. Next.js handles SIGTERM unless
    `NEXT_MANUAL_SIG_HANDLE` is set
    ([start-server.js L330-L366](https://unpkg.com/next@15.5.18/dist/server/lib/start-server.js)),
    and so does Storyteller's Readium service, which exits 0
    ([readiumService.ts L434-L453](https://gitlab.com/storyteller-platform/storyteller/-/blob/web-v2.14.23/applications/web/src/services/readiumService.ts#L434-453)).
    That handler's SIGTERM to the `readium` child is hit by the same denial. The `error` listener
    on that child logs it, and the child is killed when the container exits. Without tini,
    nothing reaps orphaned grandchildren. Storyteller waits on its own children (readium,
    whisper, ffmpeg), so that's acceptable. `RunInit=true` wouldn't help: catatonit forwards
    signals with `kill()` the same way. `SuccessExitStatus=1` would only hide the failed state
    while node still never got SIGTERM.
  - Not done: the same denial hits every signal between processes in any container on a host
    whose crun has its own AppArmor profile. A host-side fix belongs in a separate ticket, if one is
    wanted.
  - Verify on websvcs after `install_svcs.sh storyteller`:

    ```bash
    # Before the fix, these confirm the cause (expect the stacked label and a tini DENIED line)
    podman exec storyteller cat /proc/1/attr/current
    journalctl -k -g 'apparmor="DENIED"' | grep -E 'comm="tini"|signal'
    # After the fix
    podman top storyteller pid user args   # PID 1 is node, user 1000
    systemctl stop storyteller
    systemctl show -p ActiveState -p Result storyteller   # inactive, success
    systemctl start storyteller
    systemctl restart storyteller && systemctl is-failed storyteller   # active, not failed
    # 0; the journal, since the quadlet removes the container and its podman logs
    journalctl -u storyteller --since -10min | grep -c tini
    ```
