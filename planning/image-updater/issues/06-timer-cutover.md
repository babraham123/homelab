# 06. Disable podman-auto-update.timer, enable the updater timer

Status: ready-for-human
Type: task
Repo: homelab
Source: notes/image-updater-design.md "Changes, in rollout order" step 5
Blocked by: 01, 05

## Change

Per VM, after its quadlets are migrated (05) and with the schedule confirmed by checks
3 and 6 (01):

```bash
systemctl disable --now podman-auto-update.timer
systemctl enable --now image_updater.timer
systemctl list-timers image_updater.timer
```

## Acceptance

- `podman-auto-update.timer` is disabled on every VM.
- The first scheduled run on each VM completes and writes its textfile metric.

## Comments
