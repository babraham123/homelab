# 07. Commit a rendered copy of the repo (example values) for humans and agents

Status: resolved
Type: prototype
Repo: homelab
Source: user item 49
Blocked by: 02

## Assessment

Good idea, with two caveats. **Benefit:** anyone (or any agent) reading the repo sees
real Traefik/HAProxy/quadlet files instead of mentally executing Jinja loops, and the
generated artefacts (sudoers, routes, DNS records) become greppable. **Caveats:** every
commit touches roughly twice the files (noisy diffs), and people will edit the rendered
copy by mistake.

## Change

- `rendered/` at the repo root, produced by the pre-commit hook (ci-and-docs/02) via
  `tools/render_src.sh rendered/ --vars vars.template.yml`, then `git add rendered/`.
- `rendered/README.md`: "GENERATED from vars.template.yml — do not edit; edit `src/`".
- A CI/hook check that `rendered/` is fresh: re-render to a temp dir and `diff -r`;
  fail if it differs (catches hand edits and forgotten regenerations).
- `.fdignore`/`.gitattributes`: mark `rendered/**` as `linguist-generated` so GitHub
  collapses it in PR diffs, and exclude it from the deploy render (so it isn't copied
  onto nodes).
- `docs/development.md`: explain the directory.

## Acceptance

- Fresh clone contains `rendered/`; hook rejects a commit where it is stale.

## Answer

Done 2026-09-28 at the maintainer's request, ahead of 02.

- `.githooks/pre-commit` renders the staged tree (`vars.template.yml`), and once every
  check passes, replaces `rendered/` with it and runs `git add --all rendered`. Left out
  of the copy: `.claude`, `.githooks`, `AGENTS.md`/`CLAUDE.md`, `LICENSE` and the
  top-level `README.md`, replaced by a generated-do-not-edit `rendered/README.md`.
- Freshness: the hook regenerates on every commit instead of diffing and rejecting,
  so it can't be stale unless a commit used `--no-verify`.
- `render_src.sh` deletes `rendered/` (and `.gitattributes`) from its output and
  `.fdignore` lists it, so it isn't re-rendered or deployed. `.gitattributes` marks
  `rendered/**` `linguist-generated`.
- Documented in `docs/development.md` "Pre-commit hook and `rendered/`" and AGENTS.md.
- Not deterministic: `src/guacamole/guacamole.container.j2` renders
  `OPENID_AUTHORIZATION_ENDPOINT`'s `state` with `random`, so that one line changes in
  `rendered/` on every commit.

## Comments

- 2026-09-21 maintainer: approved; commit `rendered/` in-tree, diff noise is acceptable,
  no `rendered` branch.
