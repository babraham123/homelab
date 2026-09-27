# 07. pg_dumpall via dispatcher, triggered by the orchestrator

Status: resolved
Type: task
Repo: homelab
Source: review finding 6

## Problem

Postgres (Authelia users, Gatus history, Guacamole connections, LLDAP, Grafana) is only
captured crash-consistently inside the VM disk image.

## Change

- `src/secsvcs/commands.sh pg_dumpall`: `podman exec postgres pg_dumpall -U postgres`
  → `/var/opt/backups/postgres/pg_dumpall-<date>.sql.zst`, keep last 14, `chmod 600`.
  Use the `postgres_password` secret via `get_secret.sh` rather than trusting local
  auth.
- Add `pg_dumpall)` to `src/secsvcs/dispatcher.sh` (regenerate sudoers via the normal
  render).
- Orchestrator (issue 01) calls `ssh autoadmin@secsvcs pg_dumpall` before `vzdump`, so
  the dump lands inside the VM image that PBS captures; PBS then carries it to pbs2 and
  offsite with no extra transfer.
- Optional later: `proxmox-backup-client backup pgdump.pxar:/var/opt/backups/postgres`
  straight to pbs2 as a separate host-backup group, for finer-grained restore.

## Acceptance

- `ssh autoadmin@secsvcs pg_dumpall` produces a file; `psql -f` of it into a scratch
  container recreates all roles and databases.

## Comments

2026-09-27: Added `commands.sh pg_dumpall` (dumps over TCP to the container hostname with `PGPASSWORD` from `get_secret.sh`, so scram applies; atomic `.tmp`→final, keeps 14, `chmod 600`) and the dispatcher case; sudoers/Olive Tin pick it up via render. Added `zstd` to the Podman guide's apt list. The orchestrator call belongs to issue 01, which is blocked on this one.
Human: `apt install zstd` on secsvcs, deploy, run `ssh autoadmin@secsvcs pg_dumpall`, and test-restore into a scratch container with `psql -f`.
