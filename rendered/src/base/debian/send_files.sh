#!/bin/bash
# Bundles files for a dispatcher command that takes them on stdin (receive_files in
# src/base/lib.sh): a tar of the files, by basename or as NAME, plus their SHA256SUMS.
# Usage:
#   src/base/debian/send_files.sh PATH[=NAME]... | ssh autoadmin@NODE install_X

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

[[ $# -ge 1 ]] || die "usage: $0 PATH[=NAME]..."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
names=()
for arg in "$@"; do
  path=${arg%%=*}
  if [[ $arg == *=* ]]; then name=${arg#*=}; else name=$(basename "$path"); fi
  [[ -f $path ]] || die "not a regular file: ${path}"
  cp -- "$path" "${dir}/${name}"
  names+=("$name")
done
cd "$dir"
sha256sum -- "${names[@]}" > SHA256SUMS
tar -c -- SHA256SUMS "${names[@]}"
