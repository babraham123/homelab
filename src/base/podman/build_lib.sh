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

# Usage: base_images < CONTAINERFILE; the image refs it builds from (FROM, COPY --from),
# skipping stage names
base_images() {
  sed -nE 's/^FROM[[:space:]]+(--[^[:space:]]+[[:space:]]+)*([^[:space:]]+).*/\2/p
    s/^COPY[[:space:]]+.*--from=([^[:space:]]+).*/\1/p' |
    grep / | sort -u
}

# Usage: github_file OWNER/REPO COMMIT FILE; FILE's contents at COMMIT
github_file() { curl -fsS "https://raw.githubusercontent.com/$1/$2/$3"; }

# Usage: github_latest_release OWNER/REPO; the latest release's tag
github_latest_release() {
  curl -fsS "https://api.github.com/repos/$1/releases/latest" | jq -er .tag_name
}

# Usage: github_asset_sha OWNER/REPO TAG ASSET; ASSET's sha256, from the release's
# ASSET.sha256. Same origin as the asset, so it catches a corrupt or replaced download,
# not a compromised release.
github_asset_sha() {
  curl -fsSL "https://github.com/$1/releases/download/$2/$3.sha256" | awk '{ print $1; exit }'
}

# Usage: image_versions < CONTAINERFILE; one NAME@DIGEST line per image it builds from
image_versions() {
  local images image digest
  images=$(base_images)
  for image in $images; do
    case $image in
      # Pinned in the file, so the pin is the input; skopeo also rejects a tag with a digest
      *@*) digest=${image#*@} image=${image%@*} ;;
      *) digest=$(image_digest "$image") ;;
    esac
    echo "${image##*/}@${digest}"
  done
}

# Usage: github_build NAME OWNER/REPO FILE versions | build TAG
# A build.sh for an image built from a GitHub repo's main branch with its Containerfile
# FILE. Its inputs are the branch, by commit, and the images FILE builds from, by digest.
github_build() {
  local name=$1 repo=$2 file=$3 commit src
  case ${4:-} in
    versions)
      # Assigned before use: a failed lookup in a for list or an echo's arguments wouldn't
      # stop the script.
      commit=$(github_commit "$repo")
      echo "${name}@${commit}"
      github_file "$repo" "$commit" "$file" | image_versions
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

# Usage: github_release_build NAME OWNER/REPO ASSET CONTAINERFILE versions | build TAG
# A build.sh for an image of a GitHub repo's latest release: CONTAINERFILE, in the service's
# dir, builds from a context holding only the release's ASSET. Its inputs are the release,
# by tag and the asset's sha256, CONTAINERFILE, by hash, and the images it builds from, by
# digest.
github_release_build() {
  local name=$1 repo=$2 asset=$3 file=$4 tag sha file_sha image src
  case ${5:-} in
    versions)
      # Assigned before use, as in github_build
      tag=$(github_latest_release "$repo")
      sha=$(github_asset_sha "$repo" "$tag" "$asset")
      file_sha=$(sha256sum < "$file" | cut -d' ' -f1)
      echo "${repo#*/}@${tag}"
      echo "${asset}@sha256:${sha}"
      echo "$(basename "$file")@sha256:${file_sha}"
      image_versions < "$file"
      ;;
    build)
      image=localhost/${name}:${6:?usage: build.sh build TAG}
      src=$(mktemp -d)
      # shellcheck disable=SC2064 # src is local, so expand it now
      trap "rm -rf '$src'" EXIT
      tag=$(github_latest_release "$repo")
      sha=$(github_asset_sha "$repo" "$tag" "$asset")
      curl -fsSL -o "${src}/${asset}" "https://github.com/${repo}/releases/download/${tag}/${asset}"
      echo "${sha}  ${src}/${asset}" | sha256sum --check || die "checksum mismatch: ${asset} ${tag}"
      # --pull=always, so the base images are the ones `versions` reported
      podman build --pull=always -f "$file" -t "$image" "$src"
      ;;
    *)
      die "usage: build.sh versions | build TAG"
      ;;
  esac
}
