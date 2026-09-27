# Supply chain and upgrade safety

Unpinned images with `AutoUpdate=registry` mean unattended major-version upgrades of the
trust chain, and a third-party Traefik plugin is fetched from GitHub at startup.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-pin-container-images.md) | Pin container images and decide the AutoUpdate policy | `wontfix` (superseded by [image-updater](../image-updater/spec.md)) | task |
| [02](issues/02-vendor-traefik-rewrite-headers-plugin.md) | Fork and vendor the Traefik rewrite-headers plugin as a local plugin | `ready-for-agent` | task |
