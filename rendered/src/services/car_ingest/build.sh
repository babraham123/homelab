#!/bin/bash
# Builds localhost/car_ingest for the image updater, which scans the result before it replaces the
# running image. Its inputs are babraham123/car-ingest's latest release (its car_ingest zipapp,
# by tag and sha256), the Containerfile here, and the image it builds from, by digest. Its
# configuration is environment variables in the quadlet, so it isn't one.
# Usage:
#   src/services/car_ingest/build.sh versions    # the inputs, one per line
#   src/services/car_ingest/build.sh build TAG   # builds localhost/car_ingest:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

github_release_build car_ingest babraham123/car-ingest car_ingest \
  "$(dirname "${BASH_SOURCE[0]}")/Containerfile" "$@"
