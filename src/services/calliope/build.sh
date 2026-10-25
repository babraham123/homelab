#!/bin/bash
# Builds localhost/calliope for src/base/podman/image_updater.py, which scans the result
# before it replaces the running image. Its inputs are TTS-Narrated-Ebook-Creator's main
# branch, by commit, and the images its Containerfile builds from (FROM, COPY --from), by
# digest. The branch carries the quadlet's entrypoint, batch/calliope_batch.py, too.
# Usage:
#   src/services/calliope/build.sh versions    # the inputs, one per line
#   src/services/calliope/build.sh build TAG   # builds localhost/calliope:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

github_build calliope babraham123/TTS-Narrated-Ebook-Creator Containerfile "$@"
