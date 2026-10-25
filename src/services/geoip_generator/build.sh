#!/bin/bash
# Builds localhost/geoip_generator for src/base/podman/image_updater.py, which scans the
# result before it replaces the running image. Its inputs are babraham123/haproxy-mapper's
# main branch, by commit, and the images its geoip_generator.Containerfile builds from, by
# digest.
# Usage:
#   src/services/geoip_generator/build.sh versions    # the inputs, one per line
#   src/services/geoip_generator/build.sh build TAG   # builds localhost/geoip_generator:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

github_build geoip_generator babraham123/haproxy-mapper geoip_generator.Containerfile "$@"
