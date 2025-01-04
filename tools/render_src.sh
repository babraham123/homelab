#!/usr/bin/env bash
# Renders the source code into the given folder. Fills in personal details from vars.yml.
# Run from root of the project directory.
# Usage:
#   cd ~/project/dir
#   tools/render_src.sh /dir/to/store/rendered/copy
# Ref:
# https://manpages.debian.org/buster/fd-find/fdfind.1.en.html
# https://github.com/kpfleming/jinjanator
# Note:
# The *.j2 extension indicates that the file will go thru a second pass of jinjanate,
# usually during service startup. See src/podman/render_secrets.sh for an example.

set -euo pipefail

# Prepare the output directory
project_dir=$1
rm -rf "$project_dir" all_vars.yml
mkdir -p "$project_dir"
cp -R . "$project_dir"
pushd "$project_dir"
rm -rf .git .gitignore vars.yml .vscode .fdignore
popd

# Assemble jinja2 config file
cut_line=$(grep -n "^\.\.\." vars.yml | cut -d: -f1)
{
  # Exclude the ending "..."
  head -n "$((cut_line-1))" vars.yml
  
  tools/parse_routes.sh secsvcs
  tools/parse_routes.sh homesvcs
  tools/parse_uptime_urls.sh src/gatus/config.yaml
  echo -e "...\n"
} > all_vars.yml

# Render the files
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
$fdfind . --type f --exec jinjanate --quiet -o "$project_dir/{}" "{}" all_vars.yml

rm -f all_vars.yml
cd "$project_dir"

# Make executable
$fdfind . --extension sh --exec chmod +x "{}"
$fdfind . --extension pl --exec chmod +x "{}"

# Validate yaml files
if ! yamllint -c lint.yaml .; then
  echo "error: yaml linting failed" >&2
  exit 1
fi

# Validate json files
$fdfind . --extension json | xargs -I% \
  sh -c 'jq -e . % > /dev/null || { echo "error: json validation failed: %" >&2; exit 1; }'

# Validate unique IPs
$fdfind . --extension container | xargs grep -h "IP=" | \
  sort | uniq -d | grep . && { echo "error: duplicate IPs found" >&2; exit 1; }

rm -f "$project_dir"/**/.DS_Store
echo "Rendered the repo into $project_dir"
