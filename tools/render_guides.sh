#!/usr/bin/env bash
# Renders the guide files into the given folder. Fills in fake details from vars.template.yml.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/render_guides.sh /dir/to/store/rendered/copy
# Ref:
# https://manpages.debian.org/buster/fd-find/fdfind.1.en.html
# https://github.com/kpfleming/jinjanator

set -euo pipefail

# Prepare the output directory
project_dir=$1
rm -rf "$project_dir"
mkdir -p "$project_dir"
cp -R docs/guides/* "$project_dir"

# Render the files
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"

cd docs/guides
$fdfind . --type f --exec jinjanate --quiet -o "../../$project_dir/{}" "{}" ../../vars.template.yml

echo "Rendered the guides into $project_dir"
