#!/bin/bash
# Builds localhost/bookmark_handoff for the image updater, which scans the result before it
# replaces the running image. Its inputs are babraham123/bookmark-handoff's latest release (its
# bookmark_handoff zipapp, by tag and sha256), the Containerfile here, and the image it builds
# from, by digest.
# Usage:
#   src/services/bookmark_handoff/build.sh versions    # the inputs, one per line
#   src/services/bookmark_handoff/build.sh build TAG   # builds localhost/bookmark_handoff:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

github_release_build bookmark_handoff babraham123/bookmark-handoff bookmark_handoff \
  "$(dirname "${BASH_SOURCE[0]}")/Containerfile" "$@"
