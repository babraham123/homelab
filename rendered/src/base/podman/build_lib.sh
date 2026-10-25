# shellcheck shell=bash
# Helpers for the src/services/<service>/build.sh scripts that the image updater runs,
# sourced after lib.sh:
#   # shellcheck source=src/base/podman/build_lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/../../base/podman/build_lib.sh"
# A build.sh's `versions` names every input of the image, so any of them moving
# rebuilds it through the scan gate.

# Usage: image_digest REF; REF's current remote digest
image_digest() { skopeo inspect --no-tags "docker://$1" | jq -r .Digest; }

# Usage: github_commit OWNER/REPO [BRANCH]; the branch's head commit, default main
github_commit() {
  curl -fsS -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/$1/commits/${2:-main}"
}

# Usage: github_source OWNER/REPO COMMIT DIR; extracts the repo at COMMIT into DIR
github_source() {
  mkdir -p "$3"
  curl -fsSL "https://github.com/$1/archive/$2.tar.gz" | tar -xz -C "$3" --strip-components=1
}

# Usage: github_base_images OWNER/REPO COMMIT FILE; the image refs FILE (a Containerfile)
# builds from (FROM, COPY --from), skipping stage names
github_base_images() {
  curl -fsS "https://raw.githubusercontent.com/$1/$2/$3" |
    sed -nE 's/^FROM[[:space:]]+(--[^[:space:]]+[[:space:]]+)*([^[:space:]]+).*/\2/p
      s/^COPY[[:space:]]+.*--from=([^[:space:]]+).*/\1/p' |
    grep / | sort -u
}

# Usage: github_build NAME OWNER/REPO FILE versions | build TAG
# A build.sh for an image built from a GitHub repo's main branch with its Containerfile
# FILE. Its inputs are the branch, by commit, and the images FILE builds from, by digest.
github_build() {
  local name=$1 repo=$2 file=$3 commit images image digest src
  case ${4:-} in
    versions)
      # Assigned before use: a failed lookup in a for list or an echo's arguments wouldn't
      # stop the script.
      commit=$(github_commit "$repo")
      images=$(github_base_images "$repo" "$commit" "$file")
      echo "${name}@${commit}"
      for image in $images; do
        digest=$(image_digest "$image")
        echo "${image##*/}@${digest}"
      done
      ;;
    build)
      src=$(mktemp -d)
      # shellcheck disable=SC2064 # src is local, so expand it now
      trap "rm -rf '$src'" EXIT
      commit=$(github_commit "$repo")
      github_source "$repo" "$commit" "$src"
      # --pull=always, so the base images are the ones `versions` reported
      podman build --pull=always -f "${src}/${file}" \
        -t "localhost/${name}:${5:?usage: build.sh build TAG}" "$src"
      ;;
    *)
      die "usage: build.sh versions | build TAG"
      ;;
  esac
}
