# Container hardening

Across 31 quadlets only `NoNewPrivileges=true` is set. Survey what each container
tolerates before adding `DropCapability`, `ReadOnly`, `Tmpfs` and `HealthCmd`.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-capabilities-readonly-tmpfs-survey.md) | Survey: which containers can drop capabilities, run read-only, and use tmpfs | `ready-for-agent` | research |
| [02](issues/02-healthcmd-survey.md) | Survey: which containers support a HealthCmd, and with what | `ready-for-agent` | research |
