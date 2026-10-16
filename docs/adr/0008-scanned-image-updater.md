# ADR 0008: Per-node scanned image updater instead of registry auto-update

Status: accepted (2026-10-11)

## Context

Every quadlet ran `AutoUpdate=registry` on `podman-auto-update.timer`: whatever upstream pushed to a
tag was pulled and restarted the same night, unscanned, on every node at once. A compromised or
broken upstream image reached the containers with nothing in between, and a failed update was only
noticed when a service broke.

## Decision

- Quadlets name `localhost/` images only: `Image=localhost/<namespace>/<name>:<tag>` (the upstream
  ref without its registry host) or `localhost/<name>:latest` for images built on the node, with
  `AutoUpdate=local`. The upstream ref lives in the node inventory (`upstream:`, `build:`,
  `update_last:`), and the render fails if a quadlet's `Image=` doesn't match it. Nothing in a
  quadlet can pull, so an unscanned image can't reach a container.
- Each node that runs quadlets (vpnsvcs, homesvcs, websvcs, secsvcs) runs
  `src/base/podman/image_updater.py` on its own timer, 30 minutes apart, the notification path on
  secsvcs last. For each image in update order (install order, `update_last` entries at the end):
  compare the upstream digest with the one handled last (remote against remote), download it by
  digest, scan it with Trivy, tag the current image `:rollback`, load the new one, and run
  `podman auto-update`. A container whose update fails is pointed back at `:rollback` and that
  digest isn't retried until upstream moves.
- The scan gate blocks on fixable HIGH or CRITICAL findings only (`--ignore-unfixed`); the old image
  keeps running. Two overrides, both needing a person: a `.trivyignore` entry in git with an `exp:`
  date and a reason, or `accept` run through sudo by manualadmin on the node, which passes one exact
  digest, or one exact set of `build.sh` inputs for a built image. Neither is reachable through
  autoadmin, the dispatcher or OliveTin.
- Installing a service goes through the same gate: `install_svcs.sh` loads the service's images
  before copying its quadlets, and a block stops the install.
- Built images are rebuilt when the inputs their `build.sh` reports change (commits, base image
  digests), to `:candidate`, scanned from a `podman save` archive, then swapped in like a pulled
  image. The render requires a `build.sh` for every built image, so none skips the gate.
- The script reports itself: ntfy priorities by outcome, and textfile metrics with an
  `ImageUpdaterStale` age alert (age, not `absent()`, so a powered-off websvcs stays quiet). The
  alerting path itself is watched by the VPS dead-man (`deadman.sh`), so no second heartbeat.

## Considered

- **A zot registry on secsvcs** as the single scanned source, with central ingest and builds: one
  scan per image instead of one per node, but a registry, its htpasswd, per-node auth files, an
  internal-CA cert and firewall rules to run, and secsvcs on the update path of every node.
- **`Pull=newer` in quadlets**: still pulls unscanned images, on every restart instead of nightly.
- **Pinned digests in git**, updated by hand or a bot: every update becomes a
  commit and a deploy, which in practice means updates stop.
- **An `OnFailure=` hook on `podman-auto-update.service`**: it reports failures but scans nothing.
- **A Gatus heartbeat** as a second dead-man path: Gatus alerts only through vmalert's
  `EndpointDown`, the same vmalert → Alertmanager → ntfy path as `ImageUpdaterStale`, so it added
  an Authelia bypass and a secret for no extra coverage.

## Consequences

- Each node downloads and scans its own images: about one Trivy DB refresh and a few downloads a
  night per node, and Docker Hub credentials on each so the shared pull limit isn't hit.
- A run must fit in its 30-minute slot. homesvcs, websvcs and vpnsvcs stop starting images after
  25 minutes and leave the rest for the next night; secsvcs, last, has no deadline.
- A CVE with no fix doesn't block, so a known-vulnerable image still runs until a fix ships.
- No health checks gate the rollout: an image that starts but misbehaves stays until Gatus or an
  alert catches it, then is rolled back by hand from `:rollback`.
