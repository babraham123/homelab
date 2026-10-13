#!/bin/bash
# Creates Guacamole's tables in Postgres. Run once, after postgres is installed.
# Usage:
#   /root/homelab-rendered/src/nodes/secsvcs/init_guacamole_db.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

require_root

container=$(podman container ls | grep postgres | awk '{print $1}')
password=$("${rendered}/base/podman/get_secret.sh" guacamole_pg_password)

podman run --rm --rmi docker.io/guacamole/guacamole:1.6.0 /opt/guacamole/bin/initdb.sh --postgresql \
  | podman exec -i -e PGPASSWORD="$password" --user 70 "$container" psql -U guacamole -d guacamole
