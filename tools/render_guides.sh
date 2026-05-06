#!/bin/bash
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
cd docs/guides
if [[ ! "$project_dir" = /* ]]; then
  project_dir="../../${project_dir}"
fi

rm -rf "$project_dir"
mkdir -p "$project_dir"
cp -R . "$project_dir"

# Render the files
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"

$fdfind . --type f -e j2 --exec rm "${project_dir}/{}"
$fdfind . --type f -e j2 --exec jinjanate --quiet -o "${project_dir}/{.}" "{}" ../../vars.template.yml

rm -f "${project_dir}"/**/.DS_Store

echo "Rendered the guides into ${1}"
