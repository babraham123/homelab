# 03. Staging: a clone-test-destroy runbook rather than a standing environment

Status: wontfix
Type: task
Repo: homelab
Source: review finding 47 (maintainer asked how helpful it would be)

## How helpful would staging actually be? (answer)

Moderately, and less than the other items. For a single operator, a standing staging VM
costs upkeep and drifts. Most of the value — syntax and schema errors — is captured more
cheaply by rendering against `vars.template.yml` plus the per-service validators in
ci-and-docs/02. What staging *uniquely* catches is runtime integration: an Authelia ↔
LLDAP change, a Traefik middleware chain, an image bump that starts but misbehaves.

## Cheapest version worth having

Not an environment, a runbook in `docs/development.md`:

1. `qm clone <secsvcs id> 9xxx --name secsvcs-test --full` on pve1 (LVM-thin, fast).
2. Boot on an isolated bridge or with a different static IP; point a hosts-file entry
   at it from the workstation.
3. `upload_src.sh secsvcs-test` + `install_<svc>`; exercise login.
4. `qm destroy 9xxx`.

Recommend: do ci-and-docs/02 first, run this runbook only before risky changes (Authelia
major bumps, LLDAP key seed, Traefik plugin change). Revisit a standing environment only
if that becomes frequent.

## Comments

- 2026-09-21 maintainer: ignore staging for now. Runbook idea retained above for later.
