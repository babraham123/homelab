#!/bin/bash
# Builds localhost/finance_exporter for the image updater, which scans the result before it
# replaces the running image. Its inputs are babraham123/finance-exporter's main branch, by
# commit, and the images its Dockerfile builds from, by digest. config.yaml is mounted at
# run time, so it isn't one.
# Usage:
#   src/services/finance_exporter/build.sh versions    # the inputs, one per line
#   src/services/finance_exporter/build.sh build TAG   # builds localhost/finance_exporter:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

github_build finance_exporter babraham123/finance-exporter Dockerfile "$@"
