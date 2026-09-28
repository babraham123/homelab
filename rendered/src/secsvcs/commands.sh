#!/bin/bash
# Usage:
#   src/secsvcs/commands.sh CMD

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail
cd /home/autoadmin

case $1 in
  install_certs)
    # Move the certificates to their respective directories.
    chown root:root ./*.pem
    mkdir -p /etc/opt/authelia/certificates
    mkdir -p /etc/opt/lldap/certificates
    mkdir -p /etc/opt/traefik/certificates
    mkdir -p /etc/opt/db/certificates
    mkdir -p /etc/opt/gatus/certificates
    mkdir -p /etc/opt/grafana/certificates

    mv auth.janedoe.com.cert.pem /etc/opt/authelia/certificates/auth.cert.pem
    mv ldap.janedoe.com.cert.pem /etc/opt/lldap/certificates/ldap.cert.pem
    cp /etc/opt/lldap/certificates/ldap.cert.pem /etc/opt/authelia/certificates

    mv pgdb.janedoe.com.cert.pem /etc/opt/db/certificates/pgdb.crt
    chown 70:70 /etc/opt/db/certificates/*.crt
    # https://github.com/docker-library/postgres/blob/master/14/alpine3.19/Dockerfile

    mv secproxy.janedoe.com.cert.pem /etc/opt/traefik/certificates/proxy.crt
    mv secproxy.janedoe.com.client_cert.pem /etc/opt/traefik/certificates/proxy.client.crt
    cp /etc/opt/traefik/certificates/proxy.client.crt /etc/opt/authelia/certificates/secproxy.client.pem

    mv webproxy.janedoe.com.client_cert.pem /etc/opt/authelia/certificates/webproxy.client.pem
    mv homeproxy.janedoe.com.client_cert.pem /etc/opt/authelia/certificates/homeproxy.client.pem
    
    cp ca-chain.cert.pem /etc/opt/traefik/certificates/ca.chain.crt
    cp ca-chain.cert.pem /etc/opt/authelia/certificates/ca.chain.pem
    cp ca-chain.cert.pem /etc/opt/lldap/certificates/ca.chain.pem
    cp ca-chain.cert.pem /etc/opt/db/certificates/ca.chain.crt
    cp ca-chain.cert.pem /etc/opt/gatus/certificates/ca.chain.pem
    cp ca-chain.cert.pem /etc/opt/grafana/certificates/ca.chain.pem

    rm -rf ./*.pem
    ;;
  install_keys)
    # Move the SSL keys into their respective locations.
    chown root:root ./*.pem
    mkdir -p /etc/opt/authelia/certificates
    mkdir -p /etc/opt/lldap/certificates
    mkdir -p /etc/opt/traefik/certificates
    mkdir -p /etc/opt/db/certificates

    mv auth.janedoe.com.key.pem /etc/opt/authelia/certificates/auth.key
    mv ldap.janedoe.com.key.pem /etc/opt/lldap/certificates/ldap.key.pem

    mv secproxy.janedoe.com.key.pem /etc/opt/traefik/certificates/proxy.key

    mv pgdb.janedoe.com.key.pem /etc/opt/db/certificates/pgdb.key
    chown 70:70 /etc/opt/db/certificates/pgdb.key
    # https://github.com/docker-library/postgres/blob/master/14/alpine3.19/Dockerfile

    rm -rf ./*.pem
    ;;
  install_olive_tin_cert)
    mkdir -p /etc/opt/olive_tin/ssh
    ls id_ed25519-cert.pub
    mv ./id_ed25519* /etc/opt/olive_tin/ssh
    mv ./known_hosts /etc/opt/olive_tin/ssh
    chmod 644 /etc/opt/olive_tin/ssh/known_hosts
    ;;
  pg_dumpall)
    # Lands inside the VM disk, so the PBS snapshot of secsvcs carries it offsite.
    backup_dir=/var/opt/backups/postgres
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"
    umask 077
    dump_file="${backup_dir}/pg_dumpall-$(date +%Y-%m-%dT%H%M%S).sql.zst"
    PGPASSWORD="$(/usr/local/bin/get_secret.sh postgres_password)"
    export PGPASSWORD
    # Connect via the container hostname, not the socket or loopback, so pg_hba's
    # scram-sha-256 rule applies instead of the image's trust rules.
    if ! podman exec -e PGPASSWORD postgres \
        pg_dumpall -h pgdb.janedoe.com -U postgres | zstd -q -o "${dump_file}.tmp"; then
      rm -f "${dump_file}.tmp"
      echo "error: pg_dumpall failed" >&2
      exit 1
    fi
    mv "${dump_file}.tmp" "$dump_file"
    chmod 600 "$dump_file"
    # Keep the newest 14; the ISO timestamp makes name order chronological
    find "$backup_dir" -maxdepth 1 -name 'pg_dumpall-*.sql.zst' | sort | head -n -14 | xargs -r rm -f
    ls -l "$dump_file"
    ;;
  build_haproxy_mapper)
    # Doesn't need to run as root
    git clone https://github.com/babraham123/haproxy-mapper.git mapper
    cd mapper
    podman build --platform linux/amd64 -o type=local,dest=. .
    mv haproxy-mapper ..
    cd ..
    rm -rf mapper
    ;;
  *)
    echo "error: unknown file type: $1" >&2
    exit 1
    ;;
esac
