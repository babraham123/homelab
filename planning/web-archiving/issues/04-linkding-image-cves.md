# 04. Clear the linkding and storyteller scan-gate holds

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-26
Check by: 2026-11-09

## Problem

linkding's first install on websvcs was blocked by the scan gate. Upstream's `latest-plus` digest
`sha256:1ba3d9ebb8be8944f771acd9bdf75d3a5d192e1fca779fe005a02fe2b798958a` was on Debian 13.1 with
fixable CVEs, so it was let through with `image_updater accept linkding`. The accept covers only
that digest.

Findings that matter for linkding:

- chromium 152 has three CRITICALs, fixed in 155. The `plus` image renders every bookmarked page in
  Chromium for its snapshot, so this is untrusted input.
- PyJWT 2.13.0 has a CRITICAL, fixed in 2.14.0. djangorestframework 3.17.2 (fixed in 3.18.2) and
  Django 6.0.7 (fixed in 6.0.8) are also flagged.

The rest are build headers (`linux-libc-dev`, `libpq-dev`, `libssl-dev`) and npm tooling, which
aren't reachable at runtime.

## Plan

By the check date, look for a newer upstream digest:

```bash
# On websvcs as root
journalctl -u image_updater | grep linkding
podman inspect --format '{{.ImageDigest}}' linkding
skopeo inspect docker://docker.io/sissbruecker/linkding:latest-plus | jq -r .Digest
```

- **A newer digest loaded cleanly:** resolve this ticket.
- **A newer digest is still blocked on chromium:** the nightly ntfy alert says so. Add a `build.sh`
  in `src/services/linkding/` that runs `apt-get upgrade` on top of `latest-plus`. That fixes the
  Debian packages, chromium included. For the Python findings that remain, use a dated
  `.trivyignore`.
- **No newer digest:** do the same build.

## Storyteller

storyteller isn't installed: the scan gate blocks every digest so far. `web-v2` (2.14.23, built
2026-10-01) ships Next 15.5.18. The quadlet now tracks `web-v3.0.0-beta`, which ships Next 16.3.8.
Both have Next's unauthenticated RCEs, GHSA-2464-fhr4-w9xw and GHSA-673q-mjm6-r5xr, which are
fixed in 16.4.1.

- `src/services/storyteller/.trivyignore` waives piscina and sharp until 2026-12-31.
- tar, lodash, undici, picomatch, brace-expansion and ip-address still block, as does readium's
  Go 1.26.3, unless upstream bumps them along with Next.

By the check date:

```bash
# On websvcs as root
trivy image --severity HIGH,CRITICAL --ignore-unfixed -q \
  --ignorefile /root/homelab-rendered/src/services/storyteller/.trivyignore \
  registry.gitlab.com/storyteller-platform/storyteller:web-v3.0.0-beta
```

- **Clean:** the nightly run loads it. Then run `install_svcs.sh storyteller` and work through
  the setup checks in narrated-ebooks issue 03.
- **Only Next is fixed:** review the remaining findings, and either waive them in `.trivyignore`
  with a reason or run `image_updater accept storyteller`.
- **3.x stable ships:** move the quadlet, inventory and `docs/services.md` to its tag.
- **Before 2026-12-31:** review the piscina and sharp waivers.

## Acceptance criteria

- [ ] The running linkding image has no fixable CRITICAL in chromium or PyJWT
- [ ] No `accept` is needed for linkding's current digest
- [ ] storyteller runs a digest with Next 16.4.1 or later
