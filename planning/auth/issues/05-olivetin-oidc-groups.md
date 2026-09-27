# 05. Test OliveTin OIDC group claims and drop the allow-everyone workaround

Status: ready-for-human
Type: task
Repo: homelab
Source: upstream OliveTin/OliveTin#1103 (https://github.com/OliveTin/OliveTin/issues/1103)

## Problem

OliveTin's OAuth2 path dropped array-valued `groups` claims, so every Authelia user got
an empty usergroup and matched no ACL. The workaround in `src/olive_tin/config.yaml.j2`
(`# TODO: revert with oauth groups are fixed`) sets `defaultPermissions` to
`view/exec/logs: true`, so **anyone who clears Authelia's `gen_access` policy can run
every OliveTin action**, including the root-level dispatcher commands. The
`command_admin` / `command_general` ACLs are defined but have no effect.

The fix (PR #1104) shipped in **3000.20.0** (2026-09-10). The maintainer kept #1103 open
until the reporter confirms it works in a release.

## Change

1. Confirm the running image is ≥ 3000.20.0 (`Image=docker.io/jamesread/olivetin:latest-3k`
   with `AutoUpdate=registry`): `podman exec olive_tin OliveTin --version`, or check the
   footer. Update with `install_olive_tin` if older.
2. In `src/olive_tin/config.yaml.j2`:
   - `defaultPermissions`: `view: false`, `exec: false`, `logs: false`; remove the TODO.
   - `admins` ACL: uncomment `addToEveryAction: true`.
   - Gaming buttons: uncomment `acls: [general]` so `command_general` users see only
     those.
3. Deploy, `install_olive_tin`, then test with two LLDAP users:

   | User's groups | Expected on `/user` | Expected actions |
   |---|---|---|
   | `command_admin` (+ `authelia_gen_access`) | Matched ACLs: `admins` | all, with logs |
   | `command_general` only (+ `authelia_gen_access`) | Matched ACLs: `general` | the two gaming buttons, no logs |
   | neither | none | none |

   Also check that the multi-group usergroup string (space-joined by default) still
   matches, e.g. a user in both groups matches both ACLs.
4. Report the result on OliveTin#1103 so it can be closed.

## Acceptance

- The three test users see exactly the table above.
- `defaultPermissions` no longer grants anything.

## Comments

- Pairs with auth/01, which moves the OliveTin OIDC client to `two_factor`; this ticket
  limits what each user can do once logged in.
