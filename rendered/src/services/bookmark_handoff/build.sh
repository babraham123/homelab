#!/bin/bash
# Builds localhost/bookmark_handoff for src/base/podman/image_updater.py, which scans the
# result before it replaces the running image. Its inputs are babraham123/bookmark-handoff's
# main branch, by commit, and the images its Containerfile builds from, by digest.
# Usage:
#   src/services/bookmark_handoff/build.sh versions    # the inputs, one per line
#   src/services/bookmark_handoff/build.sh build TAG   # builds localhost/bookmark_handoff:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

github_build bookmark_handoff babraham123/bookmark-handoff Containerfile "$@"
