# shellcheck shell=bash
# pve1's secrets, sourced after lib.sh: one age file per host, /root/secrets/<host>.yaml.age,
# encrypted to pve1's AGE key and, for a VM, to the host's SSH key too, so the file pve1 edits
# is the one the host decrypts (docs/adr/0004-sops-age-secrets.md).
#   # shellcheck source=src/nodes/pve1/secrets_lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/secrets_lib.sh"

secrets=/root/secrets

# Usage: secret_get HOST NAME; prints one of HOST's secrets
secret_get() { age -d -i "${secrets}/age.txt" "${secrets}/$1.yaml.age" | yq ".$2"; }

# Usage: secret_edit HOST; opens HOST's secrets in $EDITOR, decrypted to a private file in
# /dev/shm, then encrypts them back. A host with no file yet starts from an empty one. When
# nothing changed the file is left as is, since age's output differs on every encryption. The
# temp file is removed when the script exits.
secret_edit() {
  local host=$1 file="${secrets}/$1.yaml.age" tmp before
  local recipients=(-R "${secrets}/age.pub")
  [[ $host == pve1 ]] || recipients+=(-R "${secrets}/${host}_id_ed25519.pub")
  tmp=$(mktemp --suffix=.yaml /dev/shm/secrets.XXXXXX)
  # shellcheck disable=SC2064 # expanded now on purpose: tmp is local
  trap "rm -f '${tmp}'" EXIT
  [[ ! -e $file ]] || age -d -i "${secrets}/age.txt" "$file" > "$tmp"
  before=$(sha256sum < "$tmp")
  "${EDITOR:-vi}" "$tmp"
  [[ $(sha256sum < "$tmp") != "$before" ]] || return 0
  yq . "$tmp" > /dev/null || die "not valid YAML, so ${file} is unchanged"
  age -e "${recipients[@]}" "$tmp" > "${file}.new"
  chmod 400 "${file}.new"
  mv "${file}.new" "$file"
}
