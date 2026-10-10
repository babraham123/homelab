# 03. Memory limits for every container

Status: needs-triage Type: task Repo: homelab Source: container-hardening survey

## Scope

No quadlet sets a memory limit, so one leaking service can push its VM into the OOM killer, which
then picks a victim by its own heuristic (often postgres or victoriametrics, the biggest). PIDs are
already capped: Podman's default `pids_limit` is 2048 per container ([containers.conf(5)][cc]).

## Task

- Size each container from its observed peak plus headroom (about 1.5×, more for bursty ones:
  esphome compiles, home_assistant, archivebox, grafana rendering). Nothing scrapes per-container
  memory today; `systemctl show -p MemoryPeak <svc>` after a few weeks of uptime, or
  `podman stats --no-stream` sampled over time, gives the peak.
- Choose the mechanism and use one everywhere:
  - `MemoryMax=` (and `MemoryHigh=` below it, to throttle before the kill) under `[Service]`.
    Quadlet runs containers with `--cgroups=split`, so the container's processes sit in the
    unit's cgroup and the systemd limit covers them; confirm with
    `systemd-cgls -u <svc>.service`.
  - or the quadlet `[Container]` key `Memory=` if Podman 5.8.2 has it (check the
    [v5.8.2 key table][psu]); otherwise `PodmanArgs=--memory=`.
- An OOM kill exits the container non-zero, so `Restart=on-failure` restarts it and
  `ServiceRestartLoop` alerts on a loop. Add an alert for the near-miss:
  memory above 90% of the limit for 15 minutes.
- Check the VM's total: the sum of the limits on a node may exceed its RAM (overcommit is fine),
  but no single limit should.

## Acceptance

- Every quadlet has a memory limit with its sizing source noted in a comment.
- `systemctl show -p MemoryMax <svc>` (or `podman inspect --format '{{.HostConfig.Memory}}'`)
  shows the limit on each node.
- One forced test: a container pushed over its limit is OOM-killed, restarted, and alerted on.

[cc]: https://github.com/containers/common/blob/main/docs/containers.conf.5.md
[psu]: https://docs.podman.io/en/v5.8.2/markdown/podman-systemd.unit.5.html
