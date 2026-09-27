# Code structure

A minimal inventory to kill the parse_*.sh scripts, then a directory reshuffle, a shared
bash library, and renames.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-minimal-services-inventory.md) | Minimal per-node inventory that replaces parse_routes/parse_uptime_urls/parse_dispatcher/gen_dispatch_cmds | `ready-for-agent` | prototype |
| [02](issues/02-src-layout.md) | Restructure src/ into nodes/, services/, base/ and update every path | `ready-for-agent` | task |
| [03](issues/03-shared-bash-lib.md) | Shared bash library sourced by all scripts | `ready-for-agent` | task |
| [04](issues/04-rename-guides.md) | Rename guides to match node names | `ready-for-agent` | task |
| [05](issues/05-rename-test-to-probes.md) | Rename test/ to probes/ | `ready-for-agent` | task |
| [06](issues/06-rename-vpn-to-vpnsvcs.md) | Document every step to rename the vpn node to vpnsvcs | `ready-for-agent` | research |
| [07](issues/07-j2j2-second-pass-safety.md) | Guard the .j2.j2 second-pass templates | `wontfix` | task |
| [08](issues/08-execute-vpn-rename.md) | Rename the vpn node to vpnsvcs | `ready-for-agent` | task |
