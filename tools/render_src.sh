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

# Prepare the output directory
rm -rf "$1" all_vars.yml
mkdir -p "$1"
cp -R . "$1"
rm -rf "$1/.git" "$1/.gitignore" "$1/vars.yml" "$1/.vscode" "$1/.fdignore"

# Assemble jinja2 config file
{
  # Exclude the ending "..."
  head -n -1 vars.yml
  
  tools/parse_secsvcs_routes.sh src/secsvcs/traefik/routes.yml
  tools/parse_uptime_urls.sh src/gatus/config.yaml
  echo -e "...\n"
} > all_vars.yml

# Render the files
fdfind="fdfind"
$fdfind -h &> /dev/null || fdfind="fd"
$fdfind . --type f --exec jinjanate --quiet -o "$1/{}" "{}" all_vars.yml

rm -f all_vars.yml
cd "$1"

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

echo "Rendered the repo into $1"
