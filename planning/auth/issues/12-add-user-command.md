# 12. Add a user with one command from pve1

Status: needs-triage
Type: task
Repo: homelab
Source: maintainer request 2026-10-14
Blocked by: 09

## Problem

Adding a person is a manual checklist (`docs/maintenance.md` "Add a new user"): edit `vars.yml`,
deploy and reload the Headscale ACL, create the LLDAP user, add six or more groups by hand. After
auth/09 the ACL step disappears and every remaining admin
step is an LLDAP write, so one command can do it. What stays with the person is what must happen on
their own devices: setting a password, enrolling 2FA, installing Tailscale and setting a Vaultwarden
master password.

## Decision: pve1 only

Creating an account mints an identity that can reach the apps and the tailnet, unlike the existing
OliveTin actions, which are restarts and VM power at worst. If OliveTin's key could run it, a
compromised OliveTin container could create a family user with its own email, take the reset link,
enroll its own 2FA and persist. So `add_user` is `pve1_file_transfer: true`: the dispatcher's
`require_pve1` rejects every key but pve1's, and OliveTin gets no button. That adds no exposure;
root on secsvcs already holds `lldap_admin_password`.

## Change

1. An `add_user` dispatcher command on secsvcs (`inventory.yml`, `commands.sh.j2`),
   `pve1_file_transfer: true`. Its parameters are data on stdin, never part of the command:
   - `$SSH_ORIGINAL_COMMAND` stays an exact match; nothing is split or evaluated.
   - Read at most a few KB of stdin, parse it as JSON with stdlib, and reject unknown keys.
   - Allowlist every field: `username` `^[a-z][a-z0-9_-]{0,31}$`, `email` with a strict regex,
     `role` from the table below. No free-text display name.
2. It creates the LLDAP user and adds a hardcoded group set per role, through LLDAP's GraphQL API
   reached on the node (port 17170 isn't published; the `ldap` route is behind two-factor Authelia),
   logging in with `lldap_admin_password`. Values go in as GraphQL variables, never spliced into the
   query string. Evaluate LLDAP's bundled `bootstrap.sh` before writing the GraphQL calls. Stdlib
   only on the node.

   | Role | Groups |
   | --- | --- |
   | `family` (default) | `authelia_gen_access`, `headscale_access`, `tailscale_family`, `command_general`, `ntfy_access` |
   | `guest` | `headscale_access`, `tailscale_guests` |

   Admin groups (`*_admin`, `tailscale_admin`, `telemetry_access`) stay a deliberate manual step in
   LLDAP.
3. It sets no password: it starts Authelia's reset-password flow for the user (JSON request body),
   which emails a link through the SMTP notifier. It fails without changes if the username exists.
4. A wrapper on pve1, `src/nodes/pve1/add_user.sh USERNAME EMAIL [ROLE]`, validates the same
   patterns, builds the JSON with a JSON encoder (not string concatenation) and pipes it to
   `ssh autoadmin@secsvcs add_user`.
5. Its output is the message to send the person:
   - Set your password from the email, then register a TOTP app or security key at
     `https://auth.SITE_URL`.
   - Install Tailscale and sign in: `tailscale up --login-server https://vpn.SITE_URL:443
     --accept-routes`.
   - Family: open Vaultwarden and set a master password; an organization owner then confirms you.
6. Replace `docs/maintenance.md` "Add a new user" with the pve1 command and the remaining manual
   steps: Vaultwarden organization confirmation (needs the owner's vault key) and any admin groups.

## Acceptance

- One run from pve1 creates a working family user: after the person follows the message, they sign
  in to every `authelia_gen_access` app, and join the tailnet with family access, with no
  other admin step but the Vaultwarden confirmation.
- A `guest` run gives tailnet access matching router/03's guest checks and nothing else.
- Re-running for an existing username changes nothing and says so.
- OliveTin's key is rejected by `add_user`.
- Invalid input (bad username or email, unknown role or key, oversized stdin) is rejected by the
  wrapper and again by the dispatcher command, without touching LLDAP.

## Comments
