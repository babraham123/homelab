# 06. Move geoip_generator into the haproxy-mapper fork

Status: resolved
Type: task
Repo: haproxy-mapper (fork), homelab
Source: maintainer request 2026-10-25

## Change

- The generator script and its Containerfile into babraham123/haproxy-mapper, the fork of the
  tool it wraps, with the output directory configurable.
- Homelab: `build.sh` builds from the fork; the quadlet and timer stay.

## Answer

Done 2026-10-25 (haproxy-mapper branch `geoip-generator`, `87266be`; homelab branch
`move-geoip-generator`).

- **Fork:** `geoip_generator.py`, output dir from `OUTPUT_DIR` (default `/etc/haproxy/countries`).
  `geoip_generator.Containerfile` builds haproxy-mapper from the checkout instead of downloading
  it, with literal `FROM` lines so `github_base_images` finds them. `.dockerignore` admits the
  script. The README has a "Per-country maps" section.
- **Homelab:** `src/services/geoip_generator/build.sh` is
  `github_build geoip_generator babraham123/haproxy-mapper geoip_generator.Containerfile`; the
  script and Containerfile are gone.
- `gh repo clone` added an unused `upstream` remote (ross/haproxy-mapper) to the local clone.
