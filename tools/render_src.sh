#!/bin/bash
# Renders the source code into the given folder. Fills in personal details from vars.yml.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/render_src.sh [/dir/to/store/rendered/homelab-rendered]
# Without an argument it renders into a private temp dir and prints the path.
# VARS_FILE=vars.template.yml renders with the example values instead of vars.yml.
# Ref:
# https://manpages.debian.org/buster/fd-find/fdfind.1.en.html
# https://github.com/kpfleming/jinjanator
# Note:
# The *.j2.j2 extension indicates that the file will go thru a second pass of jinjanate,
# usually during service startup. See src/base/podman/render_secrets.sh for an example.

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

vars_file=${VARS_FILE:-vars.yml}
[ -f "$vars_file" ] ||
  die "${vars_file} not found: copy vars.template.yml to vars.yml and fill in the real values"
# The inventory is appended after the vars, so they must end with the YAML end marker
cut_line=$(grep -n -m1 "^\.\.\.[[:space:]]*$" "$vars_file" | cut -d: -f1) || true
[ -n "$cut_line" ] ||
  die "${vars_file} has no closing '...' line: end it with a line of just '...', like vars.template.yml"

# Prepare the output directory. The default is a mktemp (0700) parent; the name
# homelab-rendered is kept because upload_src.sh moves the tree into place by it.
project_dir=${1:-"$(mktemp -d)/homelab-rendered"}
mkdir -p "$project_dir"
# An exclude list rather than copy-then-delete, so personal details never touch the
# output, even briefly. docs/agents is instructions for coding agents, not a published doc.
rsync -a --delete \
  --exclude /.git --exclude /.github --exclude /renovate.json --exclude /.gitignore \
  --exclude /.vscode --exclude /.fdignore \
  --exclude /.claude --exclude /.scratch --exclude /planning --exclude /notes \
  --exclude /docs/agents \
  --exclude /rendered --exclude /tests --exclude /.gitattributes \
  --exclude vars.yml --exclude all_vars.yml --exclude .DS_Store \
  ./ "$project_dir/"

# The commit each node reports after upload (src/base/debian/record_deploy.sh). Only a
# checkout has one; the pre-commit hook renders an export of the index, without .git.
if [ -e .git ]; then
  {
    echo "sha=$(git rev-parse HEAD)"
    echo "dirty=$(git status --porcelain | wc -l | tr -d ' ')"
    echo "rendered_at=$(date +%s)"
  } > "${project_dir}/DEPLOYED"
fi

# Renders template $1 to $2 with data file $3. jinjanate's traceback buries the cause, so
# a failure prints just the template, its line and the Jinja error (such as
# "'foo' is undefined" for a variable missing from vars.yml).
render_template() {
  local err line
  err=$(jinjanate --quiet -o "$2" "$1" "$3" 2>&1 > /dev/null) && return
  line=$(sed -nE 's/^ *File "[^"]*\.j2", line ([0-9]+),.*/\1/p' <<< "$err" | tail -n 1)
  echo "error: ${1}${line:+:$line}: render failed: $(tail -n 1 <<< "$err")" >&2
  return 1
}

# Assemble the template data (tools/lib.sh template_vars): vars.yml without its ending
# "...", the node inventory and what tools/inventory.py derives from it. It holds
# everything in vars.yml, so it lives in its own private temp dir, outside the repo and
# the output.
vars_dir=$(mktemp -d)
trap 'rm -rf "$vars_dir"' EXIT
all_vars="${vars_dir}/all_vars.yml"
head -n "$((cut_line-1))" "$vars_file" | template_vars src/nodes > "$all_vars"

# Render the files
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
$fdfind . --type f -e j2 --exec rm "${project_dir}/{}"
export -f render_template
$fdfind . --type f -e j2 --exec bash -c 'render_template "$@"' _ "{}" "${project_dir}/{.}" "$all_vars"

cd "$project_dir"

# Make executable
$fdfind . --extension sh --exec chmod +x "{}"
$fdfind . --extension pl --exec chmod +x "{}"
$fdfind . --extension py --exec chmod +x "{}"

tools/check_rendered.py . "$all_vars"

find . -name .DS_Store -delete
echo "Rendered the repo into ${project_dir}"
