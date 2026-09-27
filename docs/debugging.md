# Debugging

Commands and procedures for diagnosing problems across the homelab, grouped by layer.
Placeholder values from `vars.template.yml` throughout (`janedoe.com`, VPS at
`12.34.56.78`). Unless noted, commands run as root on the affected node.

Start with [General triage](#general-triage), then jump to the layer that looks broken.

## General triage

Every homelab unit's description is prefixed with `Homelab: `, so it's easy to filter
the managed services from the rest of systemd.

```bash
# List managed services and their state
systemctl list-units --all | grep Homelab
systemctl --failed

# Status and recent logs for one service
systemctl status SERVICE
journalctl -eu SERVICE
journalctl -fu SERVICE                   # follow
journalctl -u SERVICE --since "1 hour ago"

# Logs from the previous boot (useful after a crash or hang)
journalctl -b -1 -e

# Timer-driven services (cert_notifier, geoip_generator, ...)
systemctl list-timers
systemctl start geoip_generator.service  # run once, now

# Resource pressure
top -o %MEM
df -h
```

## Proxmox and VMs

### Get a console without SSH

If a VM's network or SSH is broken, attach a serial console from the Proxmox host.

```bash
qm list
qm status VMID
qm set VMID -serial0 socket   # one-time; requires a VM restart to take effect
qm terminal VMID              # exit with Ctrl+O
```

### Run commands via the guest agent

Works as long as `qemu-guest-agent` is running in the VM, even with no network.

```bash
qm guest cmd VMID ping
qm guest exec VMID -- bash -c 'systemctl --failed'

# Rescue a VM that's thrashing: stop every Homelab service
qm guest exec VMID -- bash -c \
  'systemctl list-units | grep Homelab | grep -o "[a-z0-9_]*.service" | xargs systemctl stop'
```

### VM fails to start

Usually memory exhaustion on the host (especially VMs with PCI passthrough, whose RAM
is fully pinned) or a stale lock.

```bash
top -o %MEM
journalctl -e
qm config VMID
qm unlock VMID
qm start VMID                 # prints the underlying error, unlike the web UI
```

## Podman containers

### Inspect running containers

```bash
podman ps -a
podman logs --tail 100 -f CONTAINER
podman inspect CONTAINER | less
podman healthcheck run CONTAINER

# Shell into a container by name
podman exec -it "$(podman ps --filter name=grafana --format '{{.ID}}')" /bin/bash
# Some images only have sh
podman exec -it CONTAINER /bin/sh
```

### Debug a quadlet

Quadlet files in `/etc/containers/systemd/` are converted to systemd units by a
generator. If a service is missing after `systemctl daemon-reload`, the conversion
failed; the dry run prints the generated unit or the error.

```bash
/usr/lib/systemd/system-generators/podman-system-generator --dryrun

# Only a single file, in isolation
mkdir -p /root/podtest
cp /etc/containers/systemd/SERVICE.container /root/podtest/
QUADLET_UNIT_DIRS=/root/podtest \
  /usr/lib/systemd/system-generators/podman-system-generator --dryrun
```

### Test env vars and secrets with a throwaway service

`test/test.container` and `test/test_service.sh` print how Podman passes environment
variables and secrets into a container.

```bash
cp test/test_service.sh /usr/local/bin/ && chmod +x /usr/local/bin/test_service.sh
cp test/test.container /etc/containers/systemd/
systemctl daemon-reload
systemctl start test.service
journalctl -eu test
systemctl stop test

# Same thing without systemd
podman run --rm -v /usr/local/bin:/test_bin \
  --secret hs_oidc_secret_hash,type=env,target=HS_UI_HASH \
  docker.io/library/debian:trixie-slim /test_bin/test_service.sh
```

`test/counter.sh` loops until it receives SIGTERM/SIGINT; use it to check that a
container entrypoint forwards signals and shuts down cleanly.

```bash
./counter.sh & ./counter.sh & wait < <(jobs -p)
podman run --rm -v "$PWD":/root --entrypoint=/root/counter.sh \
  docker.io/library/debian:trixie-slim
```

### Volumes

Named volumes are prefixed with `systemd-` by quadlet.

```bash
podman volume ls
podman volume inspect --format '{{ .Mountpoint }}' systemd-postgresdb
# e.g. /var/lib/containers/storage/volumes/systemd-postgresdb/_data
du -sh "$(podman volume inspect --format '{{ .Mountpoint }}' systemd-vmdata)"
```

### Images

```bash
# Find every tag that points at the same digest as TAG (run on pve1)
/root/homelab-rendered/src/pve1/lookup_docker_tag.sh homeassistant/home-assistant stable

# Preview what AutoUpdate=registry would pull
podman auto-update --dry-run
```

Building an image inside a quadlet: see
[podman#22694](https://github.com/containers/podman/pull/22694).

### Known issues

- Renaming a user breaks rootless Podman storage for that user. Fix:
  [podman#24938](https://github.com/containers/podman/issues/24938#issuecomment-2851080972).
- Permission denied inside a container is usually SELinux labels, user namespaces, or
  missing capabilities. See this
  [Red Hat guide](https://www.redhat.com/sysadmin/container-permission-denied-errors)
  and the [capabilities man page](https://man7.org/linux/man-pages/man7/capabilities.7.html).

## Secrets

Node secrets are an AGE-encrypted YAML file, decrypted on demand by helper scripts
(source: `src/podman/`).

```bash
list_secrets.sh                         # all secret names
get_secret.sh lldap_admin_password      # one value
SECRET_ID=ID get_secret_by_id.sh        # resolve a podman secret ID
podman secret ls

# Equivalent raw command
age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age | yq ".SECRET_NAME"
```

On pve1 the source files are SOPS-encrypted:

```bash
sops -d /root/secrets/HOST.yaml | yq ".SECRET_NAME"
```

Use `head -c -1` to strip the trailing newline when piping a secret into a file or
another command. After editing secrets, push them with `secret_update.sh` (see
[Maintenance](maintenance.md#update-secrets)).

## Container networking

Each container VM runs a single bridge network, `systemd-net`, where containers
resolve each other by name.

### Debug shell on the container network

```bash
podman network inspect systemd-net

# netshoot has curl, dig, tcpdump, nmap, iperf, ...
podman run -it --rm --net systemd-net docker.io/nicolaka/netshoot:latest

# Or a plain Debian box
podman run --rm -it --name=test --network=systemd-net \
  docker.io/library/debian:trixie-slim /bin/bash
apt update -y && apt install -y iputils-ping net-tools dnsutils curl ldap-utils
ping nginx
curl nginx/404.html | head
```

### HTTP checks

```bash
ss -tulpn                                        # what's listening where
curl -H "Host: www.janedoe.com" http://127.0.0.1
curl -H "Host: www.janedoe.com" http://nginx:8100/  # skip Traefik
# Hit the local Traefik with the correct SNI
curl -vk --resolve www.janedoe.com:443:127.0.0.1 https://www.janedoe.com

# Basic auth
curl -u "admin:$(get_secret.sh victoriametrics_admin_password)" \
  https://metrics.janedoe.com/api/v1/query?query=up

# Throwaway web server to test a route or firewall rule
python3 -m http.server -d /tmp/webtest 80
```

### Packet capture

```bash
tcpdump -i eth0 host 12.34.56.78
tcpdump -i eth0 port 8428 -w capture.pcap
tcpdump -A -r capture.pcap | less
```

Capturing from inside a container only sees that container's traffic; the bridge
isn't in promiscuous mode. Capture on the host's bridge interface instead
(`ip a` to find it). References:
[tcpdump filters](https://www.redhat.com/sysadmin/filtering-tcpdump),
[Linux observability tools](https://www.brendangregg.com/Perf/linux_observability_tools.png),
[port lookup](https://www.speedguide.net/port.php).

### Host firewall (ufw)

```bash
ufw status verbose
ufw show listening

# Delete a rule by number
ufw status numbered
ufw delete NUM

# Temporarily log blocked packets
ufw logging medium
journalctl --since "1 hour ago" | grep -i ufw
ufw logging off
```

Check what's exposed to the internet on the VPS with [Shodan](https://www.shodan.io/)
(`https://www.shodan.io/host/VPS_IP`).

### Reset the network stack

Last resort when the Podman network is wedged. `podman system reset` deletes **all**
containers, images, and volumes, so back up volume data first.

```bash
podman network reload systemd-net   # try this first
cp -R /var/lib/containers/storage/volumes/systemd-postgresdb/_data /root/pgbackup
podman system reset
```

## DNS and mDNS

### Unicast DNS

```bash
dig +short router.janedoe.com
dig @192.168.1.1 router.janedoe.com   # ask the router directly
cat /etc/resolv.conf
```

pfSense templatizes its "DNS Resolver" settings into Unbound configs:

| File | Contents |
|------|----------|
| `/var/unbound/unbound.conf` | Main config |
| `/var/unbound/host_entries.conf` | Host overrides |
| `/var/unbound/domainoverrides.conf` | Domain overrides |
| `/var/unbound/dhcpleases_entries.conf` | DHCP static entries |

### mDNS

```bash
apt install -y mdns-scan avahi-utils
mdns-scan
avahi-browse -altr
avahi-resolve -n DEVICE.local
# macOS
dns-sd -G v4v6 DEVICE.local
```

Test mDNS from the container network with a full systemd container (Avahi needs
systemd):

```bash
podman run -d --replace --rm --name=systemd-test --network=systemd-net \
  --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
  docker.io/jrei/systemd-debian:trixie /sbin/init
podman exec -it systemd-test /bin/bash

apt update -y && apt install -y iputils-ping dnsutils avahi-utils libnss-mdns mdns-scan iproute2
systemctl enable --now avahi-daemon
avahi-browse --all -r -p
# Add mdns4_minimal to the hosts line so libc resolves .local names
vim /etc/nsswitch.conf
systemctl restart avahi-daemon
ping -c2 DEVICE.local
exit
podman rm -f systemd-test
```

Test the same thing from an application library's point of view (Node, matching
Zigbee2MQTT) with `test/mdns.js`:

```bash
podman run --replace --rm -it --name=node-test --network=systemd-net \
  docker.io/library/node:lts-trixie-slim /bin/bash
npm install -g multicast-dns bonjour-service
NODE_PATH=$(npm root -g) node   # paste in test/mdns.js
```

Don't leave `avahi-daemon` running on the container network: it answers and consumes
query responses meant for Zigbee2MQTT and other clients. mDNS crosses VLANs via the
router's mDNS bridge; `mdns-repeater` flags are documented in
[its source](https://github.com/devsecurity-io/mdns-repeater/blob/master/mdns-repeater.c#L581).

## VPN: Headscale and Tailscale

Work outward: is the node registered, is the route advertised and approved, does a
tunnel ping work, does a real packet get through?

```bash
# On the VPS
headscale nodes list
headscale nodes list-routes
journalctl -eu headscale

# On any client
tailscale status
tailscale netcheck                       # NAT type, DERP latency
tailscale ping ROUTER_TS_IP              # may go via DERP
tailscale ping --tsmp ROUTER_TS_IP       # tailscale layer only
tailscale ping --tsmp SUBNET_IP
tailscale ping --icmp SUBNET_IP          # through the subnet router
ping -c1 SUBNET_IP
curl -v SUBNET_IP
journalctl -eu tailscaled

# Routing and firewall on a Linux client
ip route
ip route show table 52                   # tailscale's routing table
iptables -S
watch -n 0.5 iptables -L -vxn            # watch counters as you send traffic
watch -n 0.5 tailscale status
```

Known issues:

- "can't load DERP map":
  [headscale#1542](https://github.com/juanfont/headscale/issues/1542#issuecomment-1712835636),
  [reddit thread](https://www.reddit.com/r/selfhosted/comments/17uu41b/headscale_cant_load_derp_map/)
- macOS clients can't reach advertised subnets:
  [tailscale#4766](https://github.com/tailscale/tailscale/issues/4766)
- More in the [VPN guide](guides/vpn.md) and Tailscale's
  [troubleshooting docs](https://tailscale.com/kb/1023/troubleshooting/).

## Ingress: HAProxy and Traefik

### HAProxy (VPS)

The [configuration manual](https://www.haproxy.org/download/2.6/doc/configuration.txt)
is the authoritative reference. Headscale's control protocol runs over
[`/ts2021`](https://github.com/juanfont/headscale/issues/526), which must be passed
through untouched.

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg   # validate config
haproxy -vv                              # build options, TLS library
openssl version

# Runtime state via the admin socket
echo "show stat" | socat stdio /run/haproxy/admin.sock | cut -d, -f1,2,18
echo "show table" | socat stdio /run/haproxy/admin.sock   # rate-limit / ban tables
```

HAProxy routes on SNI without terminating TLS. To see what SNI a client actually
sends, capture ClientHello packets and open the file in Wireshark:

```bash
tcpdump -i eth0 -s 1500 \
  '(tcp[((tcp[12:1] & 0xf0) >> 2)+5:1] = 0x01) and (tcp[((tcp[12:1] & 0xf0) >> 2):1] = 0x16)' \
  -nnXSs0 -ttt -w sni.pcap
# locally
scp manualadmin@vpn:sni.pcap .
```

### Traefik (container VMs)

Each container VM's dashboard (secproxy/homeproxy/webproxy.janedoe.com) shows loaded
routers, services, and middlewares with their errors.

```bash
journalctl -eu traefik
# Check YAML anchors/aliases expand as intended
yq 'explode(.)' /etc/opt/traefik/config/dynamic/FILE.yml
```

| Error | Likely cause |
|-------|--------------|
| `no trusted IPs provided` | Proxy protocol enabled on an entrypoint without `trustedIPs` |
| `unable to find certificate for domains` | ACME failed; falls back to the default self-signed cert |
| `the service "X@docker" does not exist` | Router references a provider that isn't enabled; use `X@file` |
| `failed to parse CA` | Bad path or PEM in `serversTransport.rootCAs` |

For certificate errors, stop Traefik, delete `acme.json`, and start it again to
re-request everything (mind Let's Encrypt rate limits).

To see requests, enable access logs for one router
([docs](https://doc.traefik.io/traefik/routing/routers/#accesslogs)), or point a
middleware or service at a request-logging container:

```bash
podman run -it --rm --net systemd-net --hostname=logger.janedoe.com \
  docker.io/cycodelabs/simple-http-logger:latest
```

## Certificates and TLS

```bash
# Inspect a cert file
openssl x509 -noout -text -in cert.pem
openssl x509 -noout -subject -issuer -enddate -ext subjectAltName -in cert.pem

# Inspect what a server actually presents
openssl s_client -connect auth.janedoe.com:443 -servername auth.janedoe.com -showcerts </dev/null
echo | openssl s_client -connect HOST:443 -servername HOST 2>/dev/null | openssl x509 -noout -dates

# Verify against the internal CA chain (on pve1)
openssl verify -CAfile /root/ca/intermediate/certs/ca-chain.cert.pem CERT.pem
```

- Go programs read extra CA dirs from `SSL_CERT_DIR` (colon separated, replaces the
  default, so include `/etc/ssl/certs`):
  `SSL_CERT_DIR=/etc/ssl/certs:/certificates/cacerts`. See
  [root_unix.go](https://go.dev/src/crypto/x509/root_unix.go).
- `x509: certificate signed by unknown authority` from an OIDC client usually means
  it's validating a public URL (Let's Encrypt cert from Traefik) against the internal
  CA, or vice versa. Check which cert the URL actually serves with `s_client`.
- TLS between containers on the same host (e.g. Traefik → Authelia) is rarely worth it;
  the hostname won't match the cert unless you issue certs for the container names.
  See [authelia#877](https://github.com/authelia/authelia/issues/877).

### Signing a cert manually with the internal CA

Normally `src/certificates/self_signed_cert_gen.sh` does this. To sign one CSR by
hand with the passphrase from SOPS (on pve1):

```bash
cd /root/ca
openssl ca -config intermediate/openssl.cnf \
  -extensions server_cert -days 395 -notext -md sha256 \
  -passin "pass:$(sops -d /root/secrets/pve1.yaml | yq ".cert_passphrase" | head -c -1)" \
  -in intermediate/csr/HOST.csr.pem \
  -out intermediate/certs/HOST.cert.pem
chmod 444 intermediate/certs/HOST.cert.pem
openssl verify -CAfile intermediate/certs/ca-chain.cert.pem intermediate/certs/HOST.cert.pem
```

### ACME DNS challenge

Test certificate issuance with [lego](https://go-acme.github.io/lego/usage/cli/obtain-a-certificate/)
and the [acme-dns](https://github.com/cpu/goacmedns) provider, independent of Traefik:

```bash
LEGO_DEBUG_CLIENT_VERBOSE_ERROR=1 \
ACME_DNS_API_BASE=https://dns.janedoe.com \
ACME_DNS_STORAGE_PATH=/etc/opt/lego/acme_dns_accounts.json \
lego --path /var/opt/lego --email jdoe@gmail.com \
  --dns acme-dns --domains "router.janedoe.com" --accept-tos --dns-timeout 30 \
  --server https://acme-staging-v02.api.letsencrypt.org/directory \
  run
```

Drop `--server` once staging succeeds.

### CAA records

CAA records restrict which CAs may issue for the domain. At the registrar:

```
issue      letsencrypt.org
issuewild  letsencrypt.org
iodef      mailto:jdoe@gmail.com
```

Verify with `dig CAA janedoe.com` or [nslookup.io](https://www.nslookup.io/caa-lookup/).
[Reference](https://really-simple-ssl.com/instructions/edit-dns-caa-records-to-allow-lets-encrypt-ssl-certificates/).

## Identity: Authelia and LLDAP

### Startup failures

```bash
journalctl -eu authelia
```

| Error | Check |
|-------|-------|
| `LDAP Result Code 200 "Network Error"` | LLDAP up? DNS and TLS to `ldap.janedoe.com:6360` from the Authelia container |
| `LDAP Result Code 49 "Invalid Credentials"` | `lldap_admin_password` secret matches LLDAP's admin |
| `535 5.7.8 Username and Password not accepted` | SMTP password (app password) |
| ForwardAuth `StatusCode: 404` in Traefik logs | Middleware `address` points at the wrong API path for this Authelia version |

Query LLDAP directly from a debug container on `systemd-net` (see
[Container networking](#container-networking)); `ldapsearch`
[cheat sheet](https://bmaupin.github.io/wiki/applications/misc/ldapsearch.html):

```bash
LDAPTLS_REQCERT=never ldapsearch -H ldaps://lldap:6360 \
  -D "uid=admin,ou=people,dc=janedoe,dc=com" -W \
  -b "ou=people,dc=janedoe,dc=com" "(objectClass=person)" uid mail memberOf
```

LLDAP web UI login issues: [lldap#373](https://github.com/lldap/lldap/issues/373).

### OIDC integration

When an app's SSO login fails, check both the app's logs and Authelia's, then:

- `redirect_uris` for the client in `src/authelia/configuration.yml.j2` exactly match
  what the app sends.
- Client ID and secret match on both sides (`get_secret.sh APP_oidc_id`,
  `get_secret.sh APP_oidc_secret`).
- The app trusts the cert served at `auth.janedoe.com` (see
  [Certificates and TLS](#certificates-and-tls)).
- Authelia's [OIDC FAQ](https://www.authelia.com/integration/openid-connect/frequently-asked-questions/)
  and the per-app guides in its docs.

For an app with no OIDC support, prefer LDAP, then
[trusted header SSO](https://www.authelia.com/integration/trusted-header-sso/introduction/),
then plain ForwardAuth. LLDAP has
[sample client configs](https://github.com/lldap/lldap#sample-client-configurations).

### Decrypting an OAuth client's TLS traffic

When a client (e.g. Gatus using client-credentials) fails against Authelia's token
endpoint and logs aren't enough, capture and decrypt the traffic. Modern TLS uses
forward secrecy, so the server key alone can't decrypt it; the client must export
session keys via `SSLKEYLOGFILE`. `test/oauth.go.j2` is a minimal Go client that
does this.

```bash
# Build and run the test client
go mod init oauth && go get golang.org/x/oauth2 golang.org/x/oauth2/clientcredentials
go build -o oauth
tcpdump -i vmbr0 host 12.34.56.78 -w capture.pcap &
CLIENT_ID="$(get_secret.sh gatus_oidc_id)" CLIENT_SECRET="$(get_secret.sh gatus_oidc_secret)" ./oauth
kill %1

# Decrypt with the exported keys
apt install -y tshark
tshark -o tls.keylog_file:ssl_key.log -r capture.pcap -V -R "http.request || http.response"
```

To reproduce with Gatus itself, build it from source and run with
`GATUS_LOG_LEVEL=DEBUG GATUS_CONFIG_PATH=config.yaml ./gatus` against a minimal
config with one `oauth2` endpoint.

### Run Authelia outside a container

Useful to iterate on `configuration.yml` quickly. Download a release binary, write
each secret to a file, and point the `*_FILE` env vars at them:

```bash
get_secret.sh authelia_jwt_secret | head -c -1 > authelia_jwt_secret
# ...one file per secret below; edit certificates_directory in configuration.yml
AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE=authelia_jwt_secret \
AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE=lldap_admin_password \
AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE=authelia_storage_key \
AUTHELIA_STORAGE_POSTGRES_PASSWORD_FILE=authelia_pg_password \
AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE=authelia_smtp_password \
AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET_FILE=oidc_hmac_secret \
AUTHELIA_SERVER_DISABLE_HEALTHCHECK=true \
  ./authelia-linux-amd64 --config configuration.yml
```

Match the env var list to the `Secret=` lines in `src/authelia/authelia.container.j2`.

## Databases

```bash
# psql inside the postgres container (UID 70 is the postgres user in Alpine images)
podman exec -it --user 70 "$(podman ps --filter name=postgres --format '{{.ID}}')" psql
```

```sql
\l                -- list databases
\c authelia       -- connect
\dt               -- list tables
\du               -- list roles
```

To start a database from scratch, stop every dependent service, then remove its
volume. This deletes the data.

```bash
systemctl stop postgres
podman volume rm systemd-postgresdb
systemctl start postgres
```

## Observability

| Endpoint | What |
|----------|------|
| `metrics.janedoe.com/targets` | Scrape targets and their errors |
| `metrics.janedoe.com/vmui` | Ad hoc metric queries |
| `logs.janedoe.com/select/vmui` | Ad hoc log queries |
| `vmalert.janedoe.com` | Alert rules, current state |
| `uptime.janedoe.com` | Gatus checks |
| `SERVICE:PORT/metrics` | Raw metrics from a service (e.g. `victoriametrics:8428`, `vmalert:8880`) |

Metrics and logs require basic auth (`admin` + `victoriametrics_admin_password` /
`victorialogs_admin_password`).

```bash
VM_AUTH="admin:$(get_secret.sh victoriametrics_admin_password)"
VL_AUTH="admin:$(get_secret.sh victorialogs_admin_password)"

# Instant query
curl -u "$VM_AUTH" 'https://metrics.janedoe.com/api/v1/query' --data-urlencode 'query=up == 0'

# Push a test sample (Influx line protocol)
curl -u "$VM_AUTH" -d 'test_measurement,host=debug value=1' \
  https://metrics.janedoe.com/api/v2/write

# LogsQL query: errors in the last 15 minutes
curl -u "$VL_AUTH" https://logs.janedoe.com/select/logsql/query \
  --data-urlencode 'query=_time:15m error'

# Alerts currently firing
curl https://vmalert.janedoe.com/api/v1/alerts
```

If logs are missing, check `journalctl -eu fluentbit` on the source VM. If metrics are
missing, check the target on the targets page, then `vmagent` logs on that VM.

## Notifications: ntfy and email

```bash
# Subscribe to a topic (streams JSON)
curl -s -u ":TOKEN" https://push.janedoe.com/TOPIC/json
# Publish
curl -u ":TOKEN" -d "hello" https://push.janedoe.com/TOPIC
```

ntfy also accepts email-to-topic over SMTP. `test/email.txt.j2` is a raw SMTP
session:

```bash
apt install -y netcat-openbsd
nc -N push.janedoe.com 25 < test/email.txt
openssl s_client -connect push.janedoe.com:465 -quiet < test/email.txt
```

Test outbound mail from a host (used by cert_notifier and other alerts):

```bash
echo "test" | msmtp jdoe@gmail.com
```

## Home Assistant and Zigbee

- Config secrets: `!secret name` reads `secrets.yaml`; `!env_var NAME` reads an env
  var (how container secrets are injected).
- Broken entity references across configs: run the
  [Watchman](https://github.com/dummylabs/thewatchman) report from
  Developer Tools → Actions → `watchman.report`, then read `/config/watchman_report.txt`.
- OAuth2/OIDC in Home Assistant:
  [architecture#832](https://github.com/home-assistant/architecture/issues/832).
- Zigbee2MQTT settings can be overridden by env vars; the name mapping is in
  [settings.ts](https://github.com/Koenkk/zigbee2mqtt/blob/master/lib/util/settings.ts).
- Zigbee coordinator (SLZB-06M) has its own web UI at `http://slzb-06m.local/`.
- Poor range or dropped devices: change the Zigbee channel away from Wi-Fi
  ([guide](https://www.zigbee2mqtt.io/advanced/zigbee/02_improve_network_range_and_stability.html#reduce-wi-fi-interference-by-changing-the-zigbee-channel)).
- Coordinator unreachable: see [DNS and mDNS](#dns-and-mdns); it's discovered by
  mDNS across VLANs.

## pfSense (router)

```bash
service -e                       # enabled services
pfctl -sr                        # loaded firewall rules
pfctl -ss | grep IP              # state table entries for an IP
unbound-checkconf /var/unbound/unbound.conf
/etc/rc.restart_webgui           # when the web UI hangs

# Hand-edit the config (last resort), then drop the cache
vi /cf/conf/config.xml
rm /tmp/config.cache
```

### Decrypt a config backup

Encrypted backups (e.g. from Auto Config Backup) are base64-wrapped AES:

```bash
sed -e '1d' -e '$d' config-router-TIMESTAMP.xml | base64 -d | \
  openssl enc -d -aes-256-cbc -md sha256 -pbkdf2 -iter 500000 -out config.xml -k 'PASSWORD'
# Older backups: drop "-md sha256 -pbkdf2 -iter 500000"
```

### Recreate the VM

Key Proxmox settings if the router VM has to be rebuilt:

| Setting | Value |
|---------|-------|
| OS type | Linux 6.x |
| Firmware / machine | SeaBIOS, i440fx |
| CPU | 2 cores, type `host` |
| Memory | 12 GiB, ballooning off (required for PCI passthrough) |
| Disk | VirtIO SCSI single, discard on, IO thread, SSD emulation, no cache |
| Boot order | `scsi0`, `ide2` |
| Startup order | 1 (boots before everything else) |
| Network | VirtIO on `vmbr0`, firewall on; keep the old MAC so DHCP reservations hold |
| PCI devices | NIC ports passed through as `hostpci0`–`hostpci3`, in port order |

## Host administration

### Rename a user

You can't rename a user while logged in as it, so log in with a second sudo account.

```bash
ssh olduser@HOST
sudo adduser tempadmin && sudo usermod -aG sudo tempadmin
exit

ssh tempadmin@HOST
sudo pkill -KILL -u olduser
sudo usermod -l newuser -d /home/newuser -m olduser
sudo groupmod -n newuser olduser
exit

ssh newuser@HOST
ssh-keygen -c -f ~/.ssh/id_ed25519 -C "newuser@HOST"   # update key comment
sudo deluser --remove-home tempadmin
sudo reboot
```

Rootless Podman storage breaks after a rename; see
[Known issues](#known-issues).

### Remote sudo non-interactively

Type the password once and pipe it into `sudo -S`. `read -s` keeps it off the screen
and `printf` is a builtin, so it never shows up in `ps`:

```bash
read -rs -p "sudo password for HOST: " PW; echo
printf '%s\n' "$PW" | ssh manualadmin@HOST 'sudo --prompt="" -S whoami'
unset PW
```

### Hardware overview

```bash
inxi -F     # full report
inxi -G     # graphics / GPU
inxi -Fz    # full report with serials and IPs masked, safe to share
lspci -nnk  # PCI devices and bound drivers (passthrough, GPU)
```

## Windows (gaming VM)

```powershell
# OpenSSH server
Get-Service sshd
Get-WinEvent -FilterHashtable @{LogName='OpenSSH/Operational'} -MaxEvents 20 |
  Format-List TimeCreated, Message
& "C:\Windows\System32\OpenSSH\sshd.exe" -t    # validate config
notepad "C:\ProgramData\ssh\sshd_config"
Restart-Service sshd

# Other services, e.g. Sunshine
Get-Service *sunshine*
Restart-Service -Name SunshineService
```
