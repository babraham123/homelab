# 06. Restore instructions for VMs on pve1 and pve2, and a quarterly test

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 5
Blocked by: 01, 03, 07, 08

## Problem

`docs/maintenance.md` has no restore procedure. An untested backup is a hypothesis.

## Change

Add `docs/guides/restore.md`:

- **Restore one VM in place** from PBS (`qmrestore` / UI), including the
  `net.network` static IP, and re-adding the PBS storage on a rebuilt host.
- **Restore to a scratch VMID** for testing without touching production
  (`qmrestore ... --unique`, isolated bridge or no network).
- **Restore from the offsite copy** with pve2 dead (issue 03), including getting PBS
  running on new hardware first.
- **Restore application data** independent of the VM: `podman volume import` (already
  in `docs/guides/podman.md.j2`), Postgres from the `pg_dumpall` output (issue 07),
  Home Assistant from its native backup (issue 08).
- A **quarterly restore test** entry in `docs/maintenance.md`: restore secsvcs to a
  scratch VMID, boot it, confirm Authelia login works, destroy it.

## Acceptance

- One end-to-end test of the scratch-VMID restore performed and its date recorded in
  the guide.

## Comments
