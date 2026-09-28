# 01. Bring configuration.yml.j2 up to the Authelia 4.39 template

Status: resolved
Type: task
Repo: homelab
Source: review finding 32 (maintainer wants the full annotated template kept)

## Change

- Fetch the 4.39.x `config.template.yml` from the Authelia repo at the tag matching
  `Image=docker.io/authelia/authelia:4.39`.
- Diff the current `src/authelia/configuration.yml.j2` against the *4.38.10* template
  to extract exactly your customisations (uncommented keys, the `{% raw %}` blocks,
  `access_control`, OIDC clients, `{{ site.url }}` substitutions).
- Apply those customisations onto the 4.39 template; resolve renamed/deprecated keys
  from the 4.39 release notes. Update the `# v4.38.10` header.
- Validate before deploy: `podman run --rm -v $PWD/rendered:/config authelia/authelia:4.39
  authelia config validate --config /config/configuration.yml` (also becomes a
  pre-install check in ci-and-docs/02).
- Write the procedure into `docs/maintenance.md` so the next minor bump is mechanical.

## Improvements

- Confirmed 2026-09-26: `Image=docker.io/authelia/authelia:4.39` vs `# v4.38.10` header.
  Add a render-time check (next to the duplicate-IP check, or in ci-and-docs/08) that the
  header version's major.minor equals the `Image=` tag, so the two can't drift again.
- Keep the upstream template as a pristine copy (`src/authelia/config.template.yml`,
  untracked by the render via `.fdignore`) so the next bump is a three-way merge
  (`git merge-file`) instead of a hand diff.
- Pin `Image=` to the full patch tag (`4.39.x`) so "matching template" is unambiguous;
  image-updater/05 keeps it updated within the pin.

## Acceptance

- `authelia config validate` passes; login, OIDC to Grafana, and ForwardAuth still work.

## Answer

Done 2026-09-27, merged onto the v4.39.28 template.

- The `# v4.38.10` header was stale: the file was already on the 4.39.0 template
  (passkeys, `definitions`, `password_change`, `regulation.modes`), so the 4.38.10
  diff overstated the customisations. Three-way merge against 4.39.0 → 4.39.28 had four
  conflicts; all upstream changes since 4.39.0 are comment text ("behavior", `fd`
  scheme, `PRIVATE KEY` examples, docs links). No keys were renamed or removed, and the
  rendered config (real `vars.yml`) is key-for-key identical to before.
- `webauthn.display_name` is now `{{ site.name | tojson }}`: an apostrophe in
  `site.name` (as in `vars.template.yml`) broke the YAML.
- `Image=` stays on the `4.39` minor tag (maintainer decision): patch releases don't change
  the template, and `AutoUpdate=registry` keeps picking them up.
- Pristine upstream copy at `src/authelia/config.template.yml`. It isn't in `.fdignore`:
  that only affects `*.j2` rendering, and a non-`.j2` file is copied unrendered anyway.
- No header-vs-image render check (maintainer decision): the bump procedure sets both.
- Bump procedure (normalise, `git merge-file`, validate on secsvcs with the quadlet's
  secrets) in `docs/maintenance.md` "Upgrade Authelia to a new minor version".
- Not yet done: `authelia config validate` with the 4.39.28 image and the
  login/OIDC/ForwardAuth checks, which need secsvcs (no podman locally).

## Comments
