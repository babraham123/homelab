#!/usr/bin/env bash
# Renders the source code into the given folder. Fills in personal details from vars.yml.
# Run from root of the project directory.
# Usage:
#   cd project/dir
#   tools/render_src.sh /dir/to/store/rendered/copy
# Ref:
# https://manpages.debian.org/buster/fd-find/fdfind.1.en.html
# https://github.com/kpfleming/jinjanator
# Note:
# The *.j2 extension indicates that the file will go thru a second pass of jinjanate,
# usually during service startup. See src/podman/render_secrets.sh for an example.

set -euo pipefail

rm -rf "$1" all_vars.yml
mkdir -p "$1"
cp -R . "$1"
rm -rf "$1/.git" "$1/.gitignore" "$1/vars.yml" "$1/.vscode"

# Exclude the ending ...
head -n -1 vars.yml > all_vars.yml
tools/parse_secsvcs_routes.sh >> all_vars.yml
echo -e "...\n" >> all_vars.yml

fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
$fdfind . --type f --exec jinjanate --quiet -o "$1/{}" "{}" all_vars.yml
$fdfind . --extension sh --exec chmod +x "$1/{}"
$fdfind . --extension pl --exec chmod +x "$1/{}"

echo "Rendered the repo into $1"
rm -f all_vars.yml
