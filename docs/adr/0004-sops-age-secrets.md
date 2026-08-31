# ADR 0004: SOPS + AGE for secrets instead of Vault

Status: accepted (backfilled 2026-08-30; decision predates this record)

## Context

Infrastructure-as-code means the repo should fully reproduce the system, but secrets
can't be committed in plaintext. Out-of-band stores (env files, password managers)
break reproducibility; HashiCorp Vault is a stateful, always-on service with its own
unsealing and availability story — heavy for a single operator.

## Decision

Write every secret to disk with SOPS using AGE as the backend. One AGE
keypair per VM, private key only on that host. SOPS encrypts YAML values but not
keys, so the file is human-readable. At container startup, `get_secret.sh` decrypts
values and `render_secrets.sh` renders them into `*.j2.j2` second-pass templates with
restricted access or into Podman secrets at `/run/secrets/<name>`.

## Consequences

- The repo, the secrets file and one AGE key reproduces a node from scratch.
- No secrets server to run; no audit log of access either — acceptable for one
  operator, wrong for a team.
- The per-host AGE key is a single point of failure: lose it and that node's secrets
  are unrecoverable.
- Rotation means re-render + restart.
