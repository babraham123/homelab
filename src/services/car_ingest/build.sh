#!/bin/bash
# Builds localhost/car_ingest for src/base/podman/image_updater.py, which scans the result
# before it replaces the running image. Its inputs are babraham123/car-ingest's main branch,
# by commit, and the images its Containerfile builds from, by digest. Its configuration is
# environment variables in the quadlet, so it isn't one.
# Usage:
#   src/services/car_ingest/build.sh versions    # the inputs, one per line
#   src/services/car_ingest/build.sh build TAG   # builds localhost/car_ingest:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

github_build car_ingest babraham123/car-ingest Containerfile "$@"
