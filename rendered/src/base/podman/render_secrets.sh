#!/bin/bash
# Renders the given file in the same directory as its template (FILENAME.j2), the second
# pass of a *.j2.j2: [[ env('SECRET') ]] and [% %] blocks (second_pass.py).
# Includes the given secrets as env vars while rendering.
# The rendered file will be owned by root.
# Usage:
#   src/base/podman/render_secrets.sh FILENAME SECRET1,SECRET2
# Ref:
# https://github.com/kpfleming/jinjanator
# https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_filters.html

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

file=$1
if [ ! -f "$file.j2" ]; then
  die "file template $file.j2 does not exist"
fi

IFS=, read -ra secrets <<< "$2"
for secret in "${secrets[@]}"; do
  echo "$secret"
  secret_value=$("$(dirname "$0")/get_secret.sh" "$secret")
  printf -v "$secret" "%s" "$secret_value"
  export "${secret?}"
done

if [ -f "$file" ]; then
  # Reset ownership and permissions
  chown root:root "$file"
  chmod 600 "$file"
fi

jinjanate --quiet --customize "$(dirname "$0")/second_pass.py" -o "$file" "$file.j2"
chmod 400 "$file"

echo "Rendered the file $file"
