# Container hardening

All 41 quadlets set `NoNewPrivileges=true`. The surveys (01, 02) found what each container tolerates,
and their `DropCapability`, `ReadOnly`, `Tmpfs` and core `HealthCmd` blocks are applied (`958b1ad`).
Memory limits (03) and `UserNS=auto` (04) are still open: no quadlet sets either.

## Issues

| # | Title | Status | Type |
| --- | --- | --- | --- |
| [01](issues/01-capabilities-readonly-tmpfs-survey.md) | Survey: which containers can drop capabilities, run read-only, and use tmpfs | `resolved` | research |
| [02](issues/02-healthcmd-survey.md) | Survey: which containers support a HealthCmd, and with what | `resolved` | research |
| [03](issues/03-memory-limits.md) | Memory limits for every container | `needs-triage` | task |
| [04](issues/04-userns-auto.md) | UserNS=auto pass, per node | `needs-triage` | task |
