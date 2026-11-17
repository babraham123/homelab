# 05. Server-side snapshots hang: AppArmor denies signals inside containers

Status: needs-triage
Type: task
Repo: homelab
Source: apply session 2026-11-17, a bookmark shared from Pinkt showed "New snapshot (failed)"

## Problem

linkding's server-side snapshot (bookmarks saved without SingleFile: Pinkt, the iOS shortcut) fails
on websvcs. The first job hangs until linkding's 120 s timeout and leaves `single-file` and
Chromium running. Every later job then fails at once, because that Chromium still holds the
profile directory.

The cause is AppArmor on the host, not the page being saved. During the failed job the kernel
logged two denials that matter, both under the profile `containers-default-0.69.2`:

| Sender | Signal | Peer label | Effect |
| ------ | ------ | ---------- | ------ |
| `node` (single-file) | TERM | `chromium//&containers-default-0.69.2` | single-file can't close its browser and waits forever |
| `python` (linkding's task worker) | TERM | `containers-default-0.69.2//&crun` | linkding can't kill single-file after the timeout: `PermissionError: [Errno 13]` |

Sender and target run as the same user (`www-data`), so the kernel's own check passes; AppArmor
is what refuses.

Why the labels are stacked:

- The host has an AppArmor profile for `crun`. A container with `NoNewPrivileges=true` can't leave
  it, so its processes carry `containers-default-…//&crun`.
- The host also has a `chromium` profile that attaches by path, so the browser inside the
  container carries `chromium//&containers-default-…`.
- Podman's default profile allows signals only to a peer with its own plain label, so a stacked
  peer never matches.

The same denial is reported upstream for rootful Podman with a `crun` profile on the host.

## Scope

Not only linkding. In the same four minutes the kernel logged 136 more signal denials on websvcs,
from `readeck` and `cscli` signalling their own threads (`signal=urg`, the Go runtime's
preemption signal). Those are noise today, but any container that signals a child is affected:
supervisors, worker pools, timeouts that kill a subprocess.

Seen on websvcs only. The other Podman nodes are unchecked.

## What's unverified

- That the snapshot itself was captured and only the cleanup hung. No denial other than the two
  signals appears in the window, and Chromium had no renderer left when inspected, which fits;
  no snapshot file was looked at.
- Which package ships the host's `crun` and `chromium` profiles, and whether anything on the host
  relies on them.

## Plan

1. On each Podman node, list the profiles and the denials:

   ```bash
   # As root
   aa-status | grep -E 'crun|chromium|containers-default'
   journalctl -k --since -1h | grep -c 'apparmor="DENIED" operation="signal"'
   ```

2. Pick the fix. Candidates, least invasive first:
   - Disable the host's `crun` and `chromium` profiles, so container labels stop stacking. Check
     first what they're for; if they only grant user namespaces to an otherwise unconfined
     binary, a rootful setup without the unprivileged-userns restriction doesn't need them.
   - Give containers a profile that also allows signals to stacked peers, set through
     `apparmor_profile` in `containers.conf`. Upstream's change adds exactly these rules; a newer
     Podman may carry it.
   - Run only linkding with AppArmor unconfined. This hides the problem for one container and
     leaves the rest.
3. Put the fix in `src/base/` so every Podman node gets it, and restart the containers so they
   pick up the new labels.

## Acceptance

- A bookmark shared from Pinkt gets a snapshot, and `podman top linkding` shows no `single-file`
  or Chromium process afterwards.
- `journalctl -k` on each Podman node shows no `apparmor="DENIED" operation="signal"` lines for
  `containers-default` over an hour of normal running.

## Comments

- 2026-11-17 agent: until this is fixed, `systemctl restart linkding` clears the stuck browser,
  and the next server-side snapshot sticks again. SingleFile uploads from the browser don't use
  this path and work.
