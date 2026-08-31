# AGENTS.md

## Purpose

Infrastructure-as-code for a self-hosted homelab: configuration files, Jinja2 templates, and bootstrap scripts for running a zero-trust private cloud on Proxmox VMs with Podman containers.

## Reference

- [Architecture overview and hardware](docs/architecture.md)
- [Networking: topology, VLANs, DNS, ingress](docs/networking.md)
- [Security: identity, TLS, secrets, host access](docs/security.md)
- [Services: container catalog, observability, backups](docs/services.md)
- [Installation](docs/installation.md)
- [Development and code structure](docs/development.md)
- [Maintenance commands](docs/maintenance.md)
- [Domain glossary](CONTEXT.md) and [decision records](docs/adr/)

## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context (`CONTEXT.md` + `docs/adr/` at repo root). See `docs/agents/domain.md`.
