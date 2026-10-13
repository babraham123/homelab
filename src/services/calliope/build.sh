#!/bin/bash
# Builds localhost/calliope for src/base/podman/image_updater.py, which scans the result
# before it replaces the running image. Its inputs are TTS-Narrated-Ebook-Creator's main
# branch, by commit, and the images its Containerfile builds from (FROM, COPY --from), by
# digest. calliope_batch.py is mounted at run time, so it isn't one.
# Usage:
#   src/services/calliope/build.sh versions    # the inputs, one per line
#   src/services/calliope/build.sh build TAG   # builds localhost/calliope:TAG

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/base/podman/build_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"

repo=babraham123/TTS-Narrated-Ebook-Creator

# Usage: base_images COMMIT; the image refs the Containerfile names, skipping stage names
base_images() {
  curl -fsS "https://raw.githubusercontent.com/${repo}/$1/Containerfile" |
    sed -nE 's/^FROM[[:space:]]+(--[^[:space:]]+[[:space:]]+)*([^[:space:]]+).*/\2/p
      s/^COPY[[:space:]]+.*--from=([^[:space:]]+).*/\1/p' |
    grep / | sort -u
}

case ${1:-} in
  versions)
    # Assigned before use: a failed lookup in a for list or an echo's arguments wouldn't
    # stop the script.
    commit=$(github_commit "$repo")
    images=$(base_images "$commit")
    echo "calliope@${commit}"
    for image in $images; do
      digest=$(image_digest "$image")
      echo "${image##*/}@${digest}"
    done
    ;;
  build)
    src=$(mktemp -d)
    trap 'rm -rf "$src"' EXIT
    commit=$(github_commit "$repo")
    github_source "$repo" "$commit" "$src"
    # --pull=always, so the base images are the ones `versions` reported
    podman build --pull=always -t "localhost/calliope:${2:?usage: $0 build TAG}" "$src"
    ;;
  *)
    die "usage: $0 versions | build TAG"
    ;;
esac
