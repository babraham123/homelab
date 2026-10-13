#!/bin/bash
# Builds localhost/geoip_generator for src/base/podman/image_updater.sh, which scans the
# result before it replaces the running image. Its inputs are the two base images, by
# digest, haproxy-mapper's main branch, by commit, and this directory's own files, so a
# deploy that changes geoip_generator.py rebuilds it too.
# Usage:
#   src/services/geoip_generator/build.sh versions    # the inputs, one per line
#   src/services/geoip_generator/build.sh build TAG   # builds localhost/geoip_generator:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
go_image=docker.io/library/golang:1-alpine
py_image=docker.io/library/python:3-alpine
mapper=babraham123/haproxy-mapper

files_hash() { cat "${dir}/geoip_generator.Containerfile" "${dir}/geoip_generator.py" | sha256sum | cut -c1-12; }

# Assigned before use: a failed lookup in an echo's or a command's arguments wouldn't stop
# the script.
go_digest=$(image_digest "$go_image")
py_digest=$(image_digest "$py_image")
mapper_commit=$(github_commit "$mapper")

case ${1:-} in
  versions)
    echo "golang@${go_digest}"
    echo "python@${py_digest}"
    echo "haproxy-mapper@${mapper_commit}"
    echo "files@$(files_hash)"
    ;;
  build)
    podman build -t "localhost/geoip_generator:${2:?usage: $0 build TAG}" \
      --build-arg "GO_IMAGE=${go_image%:*}@${go_digest}" \
      --build-arg "PY_IMAGE=${py_image%:*}@${py_digest}" \
      --build-arg "MAPPER_REF=${mapper_commit}" \
      -f "${dir}/geoip_generator.Containerfile" "$dir"
    ;;
  *)
    die "usage: $0 versions | build TAG"
    ;;
esac
