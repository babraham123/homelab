# 08. storyteller.service lands in failed after every stop

Status: needs-triage
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
