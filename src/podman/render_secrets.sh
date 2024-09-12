#!/usr/bin/env bash
# Renders the given file in the same directory as it's template (FILENAME.j2).
# Includes the given secrets as env vars while rendering.
# Assumes the rendered file will only be read by the user running the script.
# Usage:
#   /usr/local/bin/render_secrets.sh FILENAME SECRET1,SECRET2
# Ref:
# https://github.com/kpfleming/jinjanator
# https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_filters.html

set -euo pipefail

file=$1
if [ ! -f "$file.j2" ]; then
  echo "error: file template $file.j2 does not exist" >&2
  exit 1
fi

IFS=, read -ra secrets <<< "$2"
for secret in "${secrets[@]}"; do
  echo "$secret"
  secret_value=$(/usr/local/bin/get_secret.sh "$secret")
  printf -v "$secret" "%s" "$secret_value"
  export "${secret?}"
done

jinjanate --quiet -o "$file" "$file.j2"
chmod 600 "$file"

echo "Rendered the file $file"
