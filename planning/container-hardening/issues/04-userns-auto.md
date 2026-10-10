# 04. UserNS=auto pass, per node

Status: needs-triage Type: task Repo: homelab Source: container-hardening survey

Blocked by: 01

## Scope

Containers are rootful, so root in a container is root on the VM if it escapes. `UserNS=auto` gives
each container its own unprivileged uid/gid range. The per-container decisions (applied / blocked)
are in the UserNS column and the "UserNS pass" lines of
[`container_hardening.md`](../container_hardening.md).

## Task

Per node, after the caps/ReadOnly/health blocks have settled there:

1. Prerequisite, in the node's install script (nothing in the repo creates it today):
   `echo containers:2147483647:2147483648 | tee -a /etc/subuid /etc/subgid`, idempotent.
2. In each quadlet marked *applied*: `UserNS=auto`, and `idmap` appended to every `Volume=`
   (`:ro,idmap` where it's read-only). Not `:U`, which re-chowns the host path on every new range.
3. One service per commit; start with one that has no volumes (guacd), then a named volume (grafana,
   owned 472:0), then a file bind (alertmanager config).
4. Skip the blocked ones: home_assistant, archivebox (entrypoint usermod/chown), go2rtc
   (`/dev/dri`), whisper (`--gpus=all`).

## Acceptance

- `podman inspect --format '{{.HostConfig.IDMappings}}' <svc>` shows a non-zero host range for every
  *applied* container.
- Host files under each volume keep their original owners (`ls -ln`), and each service passes its
  verification loop and health check.
- Open item settled: fluentbit can still read the root-owned journal through `idmap`; if not,
  fluentbit stays without `UserNS=auto` and the guide says so.
