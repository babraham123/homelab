# 07. get_secret_by_id.sh: pass SECRET_ID via jq --arg

Status: resolved
Type: task
Repo: homelab
Source: review finding 31

## Change

`src/podman/get_secret_by_id.sh:8`:

```bash
SECRET_NAME=$(jq -r --arg id "$SECRET_ID" '.idToName[$id]' /var/lib/containers/storage/secrets/secrets.json)
```

Also guard: `[[ -n "${SECRET_ID:-}" ]] || { echo "SECRET_ID unset" >&2; exit 1; }` and
fail if `SECRET_NAME` is `null`. Same `--arg`/quoting review for `get_secret.sh` and
`list_secrets.sh` (`yq ".$secret_name"` interpolates too; use `yq --arg` or
`yq '.[$name]'` if the installed yq supports it — the Go yq uses `env(NAME)`).

## Answer

- `src/podman/get_secret_by_id.sh`: exits 1 if `SECRET_ID` is unset or empty, looks up the
  name with `jq --arg id "$SECRET_ID" '.idToName[$id]'`, and exits 1 with
  `no secret with ID <id>` when the lookup returns `null`.
- `get_secret_by_id.sh` and `get_secret.sh` now pass the secret name to yq as
  `NAME=... yq '.[strenv(NAME)]'` (the hosts run mikefarah Go yq, per the Podman/PVE1
  guides), so the name is never parsed as a yq expression.
- `list_secrets.sh` interpolates nothing and is unchanged.
- Checked against fixture files with yq v4.53.6 and jq 1.7.1. Single-line and multi-line
  values come out byte-for-byte the same as before. A missing name or ID gives `null`, and
  `SECRET_ID` unset exits 1. shellcheck 0.11.0 passes on all three scripts; on the old
  `get_secret_by_id.sh` it reported SC2086 for the unquoted `$SECRET_ID`.

## Comments
