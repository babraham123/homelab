# 07. get_secret_by_id.sh: pass SECRET_ID via jq --arg

Status: ready-for-agent
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

## Comments
