#!/bin/bash
# Renders the source code into the given folder. Fills in personal details from vars.yml.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/render_src.sh [/dir/to/store/rendered/homelab-rendered]
# Without an argument it renders into a private temp dir and prints the path.
# Ref:
# https://manpages.debian.org/buster/fd-find/fdfind.1.en.html
# https://github.com/kpfleming/jinjanator
# Note:
# The *.j2.j2 extension indicates that the file will go thru a second pass of jinjanate,
# usually during service startup. See src/base/podman/render_secrets.sh for an example.

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Prepare the output directory. The default is a mktemp (0700) parent; the name
# homelab-rendered is kept because upload_src.sh moves the tree into place by it.
project_dir=${1:-"$(mktemp -d)/homelab-rendered"}
mkdir -p "$project_dir"
# An exclude list rather than copy-then-delete, so personal details never touch the
# output, even briefly
rsync -a --delete \
  --exclude /.git --exclude /.gitignore --exclude /.vscode --exclude /.fdignore \
  --exclude /.claude --exclude /.scratch --exclude /planning --exclude /notes \
  --exclude /rendered --exclude /tests --exclude /.gitattributes \
  --exclude vars.yml --exclude all_vars.yml --exclude .DS_Store \
  ./ "$project_dir/"

# Assemble jinja2 config file. jinjanate takes one data file, so the node inventory
# (src/nodes/<node>/inventory.yml, gathered under `nodes:` in node-name order) is
# appended to vars.yml rather than passed alongside it. It holds everything in
# vars.yml, so it lives in its own private temp dir, outside the repo and the output.
vars_dir=$(mktemp -d)
trap 'rm -rf "$vars_dir"' EXIT
all_vars="${vars_dir}/all_vars.yml"
cut_line=$(grep -n "^\.\.\." vars.yml | cut -d: -f1)
{
  # Exclude the ending "..."
  head -n "$((cut_line-1))" vars.yml
  echo
  node_inventory src/nodes
  echo -e "...\n"
} > "$all_vars"

# Render the files
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
$fdfind . --type f -e j2 --exec rm "${project_dir}/{}"
$fdfind . --type f -e j2 --exec jinjanate --quiet -o "${project_dir}/{.}" "{}" "$all_vars"

cd "$project_dir"

# Make executable
$fdfind . --extension sh --exec chmod +x "{}"
$fdfind . --extension pl --exec chmod +x "{}"

tools/check_rendered.sh . "$all_vars"

find . -name .DS_Store -delete
echo "Rendered the repo into ${project_dir}"
