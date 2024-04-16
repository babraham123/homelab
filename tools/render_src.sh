#!/usr/bin/env bash
# Run from root of project directory
# tools/render_src.sh /dir/to/store/rendered/copy

# Ref:
# https://manpages.debian.org/buster/fd-find/fdfind.1.en.html
# https://github.com/kpfleming/jinjanator

set -euo pipefail

rm -rf "$1"
mkdir -p "$1"
cp -R . "$1"
rm -rf "$1/.git" "$1/.gitignore" "$1/vars.yml" "$1/.vscode"

fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
$fdfind . --type f --exec jinjanate --quiet -o "$1/{}" "{}" vars.yml
$fdfind . --extension sh --exec chmod +x "$1/{}"
$fdfind . --extension pl --exec chmod +x "$1/{}"

echo "Rendered the repo into $1"
