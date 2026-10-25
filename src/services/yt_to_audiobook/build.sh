#!/bin/bash
# Builds localhost/yt_to_audiobook for src/base/podman/image_updater.py, which scans the
# result before it replaces the running image. Its inputs are yt-to-audiobook's main branch,
# by commit, and the images its Containerfile builds from (FROM, COPY --from), by digest.
# The branch carries the quadlet's entrypoint, batch/yt_to_audiobook_batch.py, too.
# Usage:
#   src/services/yt_to_audiobook/build.sh versions    # the inputs, one per line
#   src/services/yt_to_audiobook/build.sh build TAG   # builds localhost/yt_to_audiobook:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

github_build yt_to_audiobook babraham123/yt-to-audiobook Containerfile "$@"
