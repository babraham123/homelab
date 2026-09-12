# ADR 0004: SOPS + AGE for secrets instead of a secrets manager

Status: accepted (backfilled 2026-08-30; decision predates this record; revised
2026-09-12 to match the implementation)

## Context

Infrastructure-as-code means the repo should describe the whole system, but the repo
is public and generic (real values live in the gitignored `vars.yml`), so secrets
can't be committed, even encrypted. Alternatives considered:

- A dedicated secrets manager is a stateful, always-on service with its own auth,
  backups, and availability story, and every service depends on it at startup. Heavy
  for a single operator.
- Podman's default `file` secrets driver stores values unencrypted in a JSON file
  under Podman's storage directory. It's root-only, but readable from any copy of the
  VM disk or its backups, and each value has to be maintained by hand on every host.

## Decision

Keep secrets out of git and write them to disk encrypted with SOPS and AGE.

- pve1 holds the source of truth: one SOPS file per host at
  `/root/secrets/<host>.yaml`, encrypted to pve1's AGE key. SOPS encrypts YAML values
  but not keys, so the file is human-readable.
- `src/pve1/secret_update.sh <host>` edits that file, re-encrypts it with plain `age`
  to two recipients (pve1's key and the host's ed25519 SSH key; SOPS doesn't support
  SSH keys), and installs it on the host at `/etc/opt/secrets/secrets.yaml.age`.
- Git holds only `src/<node>/secrets_template.yaml`: secret names with empty values
  and the command used to generate each one.
- Podman uses the `shell` secrets driver (`src/podman/containers.conf`). Podman stores
  only placeholder values; at container startup `get_secret_by_id.sh` decrypts the
  host file and returns the requested value.
- Apps that only read secrets from a config file use `*.j2.j2` second-pass templates:
  `ExecStartPre=` runs `render_secrets.sh`, which renders the final config root-owned
  with `chmod 400`.

## Consequences

- The repo, `vars.yml`, and the SOPS files on pve1 reproduce a node from scratch. Git
  is not a backup for secrets; the SOPS files and pve1's AGE key need their own.
- No secrets manager to run; no audit log of access either, acceptable for one
  operator, wrong for a team.
- pve1's AGE key is the single point of failure: it decrypts every host's source file.
  A lost VM key is recoverable by generating a new one and rerunning
  `secret_update.sh`.
- Values stay encrypted at rest, except in configs rendered by the second pass, which
  hold plaintext on disk (root-owned, `chmod 400`). Prefer Podman secrets wherever the
  app accepts env vars or secret files.
- Rotation means editing on pve1, redistributing with `secret_update.sh`, and
  restarting the affected services.
