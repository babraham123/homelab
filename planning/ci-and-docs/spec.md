# CI, process and documentation

No CI exists; several runbook TODOs are open; some docs and configs are stale.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-authelia-config-4.39.md) | Bring configuration.yml.j2 up to the Authelia 4.39 template | `resolved` | task |
| [02](issues/02-precommit-and-preinstall-checks.md) | Render-consistency checks in the hook; service-specific validation before install on the node | `ready-for-agent` | task |
| [03](issues/03-doc-drift-check.md) | CI check for homelab docs vs homesite copy | `wontfix` | task |
| [04](issues/04-maintenance-todos.md) | Flesh out the TODOs in maintenance.md, podman.md and proxmox.md | `ready-for-agent` | task |
| [05](issues/05-vault-stub.md) | Remove the install_vault stub | `wontfix` | task |
| [06](issues/06-remove-stale-branches.md) | Delete the stale ansible/fixes/fixes0/worktree-ntfy branches on origin | `ready-for-human` | task |
| [07](issues/07-rendered-copy-in-repo.md) | Commit a rendered copy of the repo (example values) for humans and agents | `resolved` | prototype |
| [08](issues/08-precommit-lint-hook.md) | Pre-commit hook: shellcheck, yamllint, jq, render-and-diff | `resolved` | task |
