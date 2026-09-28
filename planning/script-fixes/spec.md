# Shell script correctness fixes

Concrete bugs found in `tools/` and `src/`. Each is small and independent; shellcheck in
CI (ci-and-docs/02) prevents the class from recurring.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-dispatcher-regex-hyphen.md) | Allow hyphens in the dispatcher/sudoers generators; regenerate secsvcs dispatcher | `resolved` | task |
| [02](issues/02-mv-comments.md) | Comment the intentional mv of rendered files in install_svcs.sh | `ready-for-agent` | task |
| [03](issues/03-return-to-exit.md) | Replace top-level `return` with `exit 1` in upload scripts | `resolved` | task |
| [04](issues/04-deploy-failure-summary.md) | deploy_src.sh: collect per-host failures and exit non-zero | `ready-for-agent` | task |
| [05](issues/05-render-never-copies-secrets.md) | render_src.sh: never copy vars.yml or .git into the rendered tree | `ready-for-agent` | task |
| [06](issues/06-rm-ds-store-all-levels.md) | Make the .DS_Store cleanup recursive | `ready-for-agent` | task |
| [07](issues/07-jq-arg-secret-id.md) | get_secret_by_id.sh: pass SECRET_ID via jq --arg | `resolved` | task |
