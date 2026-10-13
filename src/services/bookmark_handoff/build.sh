#!/bin/bash
# Builds localhost/bookmark_handoff for src/base/podman/image_updater.sh, which scans the
# result before it replaces the running image. Its inputs are the base image, by digest,
# and this directory's own files, so a deploy that changes the script or a pinned
# library rebuilds it too.
# Usage:
#   src/services/bookmark_handoff/build.sh versions    # the inputs, one per line
#   src/services/bookmark_handoff/build.sh build TAG   # builds localhost/bookmark_handoff:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
py_image=docker.io/library/python:3-alpine

files_hash() {
  cat "${dir}/bookmark_handoff.Containerfile" "${dir}/bookmark_handoff.py" "${dir}/requirements.txt" |
    sha256sum | cut -c1-12
}

# Assigned before use: a failed lookup in an echo's or a command's arguments wouldn't stop
# the script.
py_digest=$(image_digest "$py_image")

case ${1:-} in
  versions)
    echo "python@${py_digest}"
    echo "files@$(files_hash)"
    ;;
  build)
    podman build -t "localhost/bookmark_handoff:${2:?usage: $0 build TAG}" \
      --build-arg "PY_IMAGE=${py_image%:*}@${py_digest}" \
      -f "${dir}/bookmark_handoff.Containerfile" "$dir"
    ;;
  *)
    die "usage: $0 versions | build TAG"
    ;;
esac
