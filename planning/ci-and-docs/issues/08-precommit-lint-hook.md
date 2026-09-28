# 08. Pre-commit hook: shellcheck, yamllint, jq, render-and-diff

Status: claimed
Type: task
Repo: homelab
Source: split out of 02 on 2026-09-26 so the lint hook doesn't wait on restructure/01

## Change

Split from 02: everything here needs no inventory and no node access, so it can land
first. Every `script-fixes` ticket names this hook as the guard against recurrence.

`.githooks/pre-commit`, activated with `git config core.hooksPath .githooks`; document
in `docs/development.md`:

1. `shellcheck -x` over `tools/*.sh`, `src/**/*.sh`, and `*.sh.j2` (render against
   `vars.template.yml` first so Jinja is gone).
2. `yamllint -c lint.yaml` on rendered YAML; `jq -e` on JSON (both already in
   `render_src.sh` — factor them into `tools/validate_rendered.sh` and call it from both).
3. Full render against `vars.template.yml` into a temp dir (`mktemp -d`, see
   script-fixes/05); duplicate-IP check.
4. Authelia header-vs-image version check (ci-and-docs/01).

Deliberately not here (stay in 02): the install_svcs↔dispatcher consistency check
(script-fixes/01), `services.yml` validation (restructure/01), and all on-node
pre-install validators.

## Acceptance

- A commit with a shellcheck error, a yamllint error in a rendered file, or a duplicate
  container IP is rejected locally.
- The hook runs in under 10 s on this repo.

## Comments
