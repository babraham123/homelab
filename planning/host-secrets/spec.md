# Host secrets

Each VM decrypts its secrets file (`/etc/opt/secrets/secrets.yaml.age`) with a copy of
`manualadmin`'s login SSH key. The key has no passphrase, so podman's lookup can decrypt unattended,
and the original stays readable in `~manualadmin/.ssh`. A shell as `manualadmin` holds the key
without needing sudo.

## Issues

| # | Title | Status | Type |
| --- | --- | --- | --- |
| [01](issues/01-separate-ssh-and-secrets-keys.md) | Give each VM a root-only secrets key, separate from manualadmin's SSH key | `ready-for-human` | task |
