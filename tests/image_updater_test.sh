# shellcheck shell=bash
# src/base/podman/image_updater.json.j2, the image updater's config, against the config
# format in github.com/babraham123/podman-image-updater's README: one hosts entry per node
# with install_image_updater, in node-name order; its images in the src/nodes.jinja update
# order, each with its service's .trivyignore and, if built, build.sh; secsvcs reaches ntfy
# straight at the container with no deadline and waits 15 minutes after boot, every other
# node through Traefik with a 25-minute deadline; every secret comes from get_secret.sh.
# shellcheck source=tests/lib.sh
source tests/lib.sh

test_config_from_the_inventory() {
  mkdir -p "${tmp}/inventory/"{secsvcs,websvcs,other} "${tmp}/jinja/src/base/podman"
  cat > "${tmp}/inventory/secsvcs/inventory.yml" <<'EOF'
debian_services: [image_updater]
services:
  ntfy:
    upstream: docker.io/binwiederhier/ntfy:v2
    update_last: true
  db:
    upstream: docker.io/library/postgres:18
EOF
  cat > "${tmp}/inventory/websvcs/inventory.yml" <<'EOF'
debian_services: [node_exporter, image_updater]
services:
  app:
    build: app
  plain: {}
EOF
  cat > "${tmp}/inventory/other/inventory.yml" <<'EOF'
debian_services: [node_exporter]
services:
  web:
    upstream: docker.io/library/nginx:stable
EOF
  cp src/nodes.jinja "${tmp}/jinja/src/"
  cp src/base/podman/image_updater.json.j2 "${tmp}/jinja/src/base/podman/"
  {
    cat tests/fixtures/site.yml
    echo "secsvcs: {container_subnet: 10.10.0}"
    node_inventory "${tmp}/inventory"
  } > "${tmp}/jinja/all_vars.yml"
  (cd "${tmp}/jinja" && jinjanate --quiet src/base/podman/image_updater.json.j2 all_vars.yml) \
    > "${tmp}/config.json"
  out=$(python3 -I - "${tmp}/config.json" <<'EOF'
import json, sys
config = json.load(open(sys.argv[1]))
hosts = config.pop("hosts")
for host, h in hosts.items():
  print(host, h.pop("ntfy"), h.pop("deadline_s"), h.pop("boot_delay_s"))
  for image in h.pop("images"):
    print(" ", json.dumps(image, sort_keys=True))
  print(" ", h)
print(config)
EOF
)
  assert_eq "$out" <<'EOF'
secsvcs {'url': 'http://10.10.0.13:2586/alert', 'token': {'command': ['/root/homelab-rendered/src/base/podman/get_secret.sh', 'ntfy_alert_token']}} 0 900
  {"container": "db", "image": "localhost/library/postgres:18", "service": "db", "trivyignore": "/root/homelab-rendered/src/services/db/.trivyignore", "upstream": "docker.io/library/postgres:18"}
  {"container": "ntfy", "image": "localhost/binwiederhier/ntfy:v2", "service": "ntfy", "trivyignore": "/root/homelab-rendered/src/services/ntfy/.trivyignore", "upstream": "docker.io/binwiederhier/ntfy:v2"}
  {}
websvcs {'url': 'https://push.example.com/alert', 'token': {'command': ['/root/homelab-rendered/src/base/podman/get_secret.sh', 'ntfy_alert_token']}} 1500 0
  {"build": "app", "build_script": "/root/homelab-rendered/src/services/app/build.sh", "container": "app", "image": "localhost/app:latest", "service": "app", "trivyignore": "/root/homelab-rendered/src/services/app/.trivyignore"}
  {}
{'registry_auth': {'docker.io': {'username': {'command': ['/root/homelab-rendered/src/base/podman/get_secret.sh', 'docker_hub_username']}, 'password': {'command': ['/root/homelab-rendered/src/base/podman/get_secret.sh', 'docker_hub_token']}}}}
EOF
}
