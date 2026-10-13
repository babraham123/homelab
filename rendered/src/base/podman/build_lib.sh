# shellcheck shell=bash
# Helpers for the src/services/<service>/build.sh scripts that image_updater.py runs,
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
