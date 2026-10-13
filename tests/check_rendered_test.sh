# shellcheck shell=bash
# tools/check_rendered.sh against tests/fixtures/tree: the fixture passes, and breaking
# each invariant fails with that invariant's error alone.
# shellcheck source=tests/lib.sh
source tests/lib.sh

test_fixture_passes() {
  fixture_tree
  out=$(check_tree) || flunk "$out"
  assert_eq "$out" < /dev/null
}

test_invalid_yaml() {
  fixture_tree
  printf -- '---\na: 1\na: 2\n...\n' > "${tmp}/tree/src/bad.yml"
  expect_errors <<'EOF'
error: src/bad.yml:3:1: duplication of key "a" in mapping (key-duplicates)
EOF
}

test_invalid_json() {
  fixture_tree
  echo '{"a": }' > "${tmp}/tree/src/bad.json"
  expect_errors <<'EOF'
error: src/bad.json: invalid JSON
EOF
}

test_markdown_lint() {
  fixture_tree
  printf '# Title\n\nNo final newline' > "${tmp}/tree/src/bad.md"
  expect_errors <<'EOF'
error: src/bad.md:3:16: MD047/single-trailing-newline Files should end with a single newline character
EOF
}

test_duplicate_container_ip() {
  fixture_tree
  printf '[Container]\nIP=10.0.0.2\n' > "${tmp}/tree/src/services/web/db.container"
  expect_errors <<'EOF'
error: src/services/web/db.container src/services/web/web.container: IP=10.0.0.2 is set in more than one quadlet
EOF
}

test_upstream_without_registry_host() {
  fixture_tree
  edit src/nodes/secsvcs/inventory.yml 's|docker.io/library/nginx|library/nginx|'
  edit src/services/web/web.container 's|^Image=.*|Image=localhost/nginx:stable|'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/inventory.yml: services.web: upstream library/nginx:stable needs a registry host and namespace
EOF
}

test_quadlet_image_mismatch() {
  fixture_tree
  edit src/services/web/web.container 's|^Image=.*|Image=docker.io/library/nginx:stable|'
  expect_errors <<'EOF'
error: src/services/web/web.container: Image=docker.io/library/nginx:stable, expected localhost/library/nginx:stable (src/nodes/secsvcs/inventory.yml services.web)
EOF
}

test_built_image_quadlet() {
  fixture_tree
  edit src/nodes/secsvcs/inventory.yml 's|upstream: docker.io/library/nginx:stable|build: web|'
  touch "${tmp}/tree/src/services/web/build.sh"
  expect_errors <<'EOF'
error: src/services/web/web.container: Image=localhost/library/nginx:stable, expected localhost/web:latest (src/nodes/secsvcs/inventory.yml services.web)
EOF
}

test_built_image_without_build_script() {
  fixture_tree
  edit src/nodes/secsvcs/inventory.yml 's|upstream: docker.io/library/nginx:stable|build: web|'
  edit src/services/web/web.container 's|^Image=.*|Image=localhost/web:latest|'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/inventory.yml: services.web: built image localhost/web:latest has no src/services/web/build.sh
EOF
}

test_install_case_copies_no_quadlet() {
  fixture_tree
  edit src/nodes/secsvcs/install_svcs.sh '/web.container/d'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/install_svcs.sh: the web case copies no web.container (src/nodes/secsvcs/inventory.yml services.web)
EOF
}

test_service_without_install_case() {
  fixture_tree
  edit src/nodes/secsvcs/install_svcs.sh '/^  db\)/,/;;/d'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/install_svcs.sh: no db case, but the secsvcs dispatcher runs it
EOF
}

test_install_case_not_in_inventory() {
  fixture_tree
  edit src/nodes/secsvcs/inventory.yml '/^  db: \{\}$/d'
  edit src/services/olive_tin/config.yaml '/install_db$/d'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/install_svcs.sh: the db case isn't in src/nodes/secsvcs/inventory.yml services
EOF
}

test_debian_service_without_case() {
  fixture_tree
  edit src/base/debian/install_svcs.sh 's/^  node_exporter\)/  exporter)/'
  expect_errors <<'EOF'
error: src/base/debian/install_svcs.sh: no node_exporter case, but the secsvcs dispatcher runs it
EOF
}

test_command_without_case() {
  fixture_tree
  edit src/nodes/secsvcs/commands.sh 's/^  install_certs\)/  install_cert)/'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/commands.sh: no install_certs case, but the secsvcs dispatcher runs it
EOF
}

test_command_script_missing() {
  fixture_tree
  edit src/nodes/secsvcs/inventory.yml 's|script: nodes/secsvcs/commands.sh|script: nodes/secsvcs/command.sh|'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/command.sh: missing, but the secsvcs dispatcher runs it
EOF
}

test_router_script_path() {
  fixture_tree
  edit src/nodes/router/commands.sh 's/^  install_certs\)/  install_cert)/'
  expect_errors <<'EOF'
error: src/nodes/router/commands.sh: no install_certs case, but the router dispatcher runs it
EOF
}

test_run_path_missing() {
  fixture_tree
  rm "${tmp}/tree/src/nodes/secsvcs/backup.sh"
  expect_errors <<'EOF'
error: src/nodes/secsvcs/backup.sh: missing, but the secsvcs dispatcher runs it
EOF
}

test_duplicate_subdomain() {
  fixture_tree
  edit src/nodes/websvcs/inventory.yml 's/blog: \{subdomain: blog\}/blog: {subdomain: www}/'
  edit src/nodes/websvcs/traefik/routes.yml 's/blog\.example/www.example/'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/inventory.yml src/nodes/websvcs/inventory.yml: subdomain www is listed more than once
EOF
}

test_subdomain_not_routed() {
  fixture_tree
  edit src/nodes/secsvcs/inventory.yml 's/db: \{\}/db: {subdomain: db}/'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/traefik/routes.yml: no Host() rule for db, listed in src/nodes/secsvcs/inventory.yml services
EOF
}

test_route_not_listed() {
  fixture_tree
  edit src/nodes/secsvcs/traefik/routes.yml 's/Host\(`www\.example\.com`\)$/Host(`www.example.com`) || Host(`db.example.com`)/'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/inventory.yml: no service has subdomain db, which src/nodes/secsvcs/traefik/routes.yml routes
EOF
}

test_default_route_subdomain_not_routed() {
  fixture_tree
  edit src/nodes/websvcs/traefik/routes.yml 's/blog\.example/news.example/'
  expect_errors <<'EOF'
error: src/nodes/websvcs/traefik/routes.yml: no Host() rule for blog, listed in src/nodes/websvcs/inventory.yml services
EOF
}

test_olive_tin_button_missing() {
  fixture_tree
  edit src/services/olive_tin/config.yaml '/autoadmin@secsvcs shutdown$/d'
  expect_errors <<'EOF'
error: src/services/olive_tin/config.yaml: no button runs secsvcs dispatcher case shutdown
EOF
}

# backup is a pve1_file_transfer in the fixture: no button, and a button for it is an error
test_olive_tin_gated_case() {
  fixture_tree
  edit src/services/olive_tin/config.yaml 's/^  - shell: ssh autoadmin@secsvcs shutdown$/&\n  - shell: ssh autoadmin@secsvcs backup/'
  expect_errors <<'EOF'
error: src/services/olive_tin/config.yaml: runs ssh autoadmin@secsvcs backup, a pve1 file transfer only pve1 may run
EOF
}

test_olive_tin_unknown_case() {
  fixture_tree
  edit src/services/olive_tin/config.yaml 's/^  - shell: ssh autoadmin@secsvcs install_certs$/  - shell: ssh autoadmin@secsvcs install_certs \&\& ssh autoadmin@websvcs install_certs/'
  expect_errors <<'EOF'
error: src/services/olive_tin/config.yaml: runs ssh autoadmin@websvcs install_certs, which isn't a websvcs dispatcher case
EOF
}

# secsvcs is a debian node in the fixture, so upload_src.sh ships it only base/ and its
# node_dirs.sh paths; a case copying from a dir no service of it names isn't among them
test_upload_dir_not_shipped() {
  fixture_tree
  mkdir -p "${tmp}/tree/src/services/shared"
  touch "${tmp}/tree/src/services/shared/db.conf"
  edit src/nodes/secsvcs/install_svcs.sh 's|mkdir -p /var/opt/db|cp services/shared/db.conf /var/opt/db|'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/inventory.yml: uses src/services/shared, which upload_src.sh doesn't ship to it; add it to a service's dirs
EOF
}

# The router isn't a debian node: it gets only its own dir, by a path of its own
test_upload_dir_other_node_unchecked() {
  fixture_tree
  mkdir -p "${tmp}/tree/src/services/shared"
  edit src/nodes/router/commands.sh 's|^case|cp services/shared/x /tmp\ncase|'
  out=$(check_tree) || flunk "$out"
  assert_eq "$out" < /dev/null
}

test_upload_dir_in_service_dirs() {
  fixture_tree
  mkdir -p "${tmp}/tree/src/services/shared"
  touch "${tmp}/tree/src/services/shared/db.conf"
  edit src/nodes/secsvcs/install_svcs.sh 's|mkdir -p /var/opt/db|cp services/shared/db.conf /var/opt/db|'
  edit src/nodes/secsvcs/inventory.yml 's|^  db: \{\}|  db: {dirs: [services/shared]}|'
  out=$(check_tree) || flunk "$out"
  assert_eq "$out" < /dev/null
}

test_upload_dir_missing() {
  fixture_tree
  edit src/nodes/secsvcs/inventory.yml 's|^  db: \{\}|  db: {dirs: [services/nope]}|'
  expect_errors <<'EOF'
error: src/nodes/secsvcs/inventory.yml: src/services/nope doesn't exist
EOF
}
