# 08. Pre-commit hook: shellcheck, yamllint, jq, render-and-diff

Status: resolved
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

## Answer

Done 2026-09-27.

- `.githooks/pre-commit` exports the index (`git checkout-index`) to a `mktemp -d` dir,
  copies `vars.template.yml` to `vars.yml`, runs `tools/render_src.sh` (so every
  render-time check runs, including the nodes.yml checks), then
  `shellcheck -x --severity=warning` over the rendered `*.sh` (covers `tools/`, `src/`,
  `test/` and rendered `*.sh.j2`). Info/style findings don't block.
- `tools/validate_rendered.sh`: yamllint, `jq -e`, duplicate `IP=`, Authelia
  header-vs-image check; `render_src.sh` calls it.
- Documented in `docs/development.md` "Pre-commit hook"; the Mac setup guide installs
  `jq shellcheck` and sets `core.hooksPath`.
- Acceptance: runs in ~6 s. A shellcheck warning, a yamllint error in rendered YAML, a
  duplicate container IP and an Authelia version mismatch each exit 1 (tested with
  patched temp indexes).
- Open findings the hook currently rejects (outside this ticket's files, so not fixed):
  - `src/certificates/self_signed_cert_gen.sh.j2`: SC1011/SC1078, `O={{ site.name }}`
    inside single quotes breaks on an apostrophe (5 `-subj` lines)
  - `src/router/commands.sh.j2:30`, `src/pve2/commands.sh.j2:19`: SC2034 unused `i`
  - `src/homesvcs/commands.sh.j2:67`: SC2174 `mkdir -p -m 700`

## Comments
