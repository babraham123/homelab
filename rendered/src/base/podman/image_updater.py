#!/usr/bin/env python3
# Keeps this node's container images current behind a vulnerability scan. For each image
# in the node inventory's update order (src/nodes.jinja images[node]) whose quadlet is
# installed: compare the upstream digest with the one handled last, download a changed
# one, scan it with Trivy (fixable HIGH or CRITICAL blocks it), load it under its
# localhost/ name and let `podman auto-update` restart the containers on it. Quadlets
# only name localhost/ images with AutoUpdate=local, so nothing unscanned reaches a
# container. Design: docs/adr/0008-scanned-image-updater.md. Standard library only.
# Usage:
#   src/base/podman/image_updater.py                  # image_updater.timer, nightly
#   src/base/podman/image_updater.py --dry-run        # check and scan; loads and restarts nothing
#   src/base/podman/image_updater.py install SERVICE  # install_svcs.sh, before copying quadlets
#   sudo src/base/podman/image_updater.py accept CONTAINER  # as manualadmin, never the dispatcher
# Overrides for a blocked image, both needing a person: src/services/<service>/.trivyignore
# (`CVE-… exp:YYYY-MM-DD`, with a `#` line giving the reason) covers every digest until it
# expires; `accept` rescans, prints the findings and passes that exact digest, or for a
# built image that exact set of build.sh inputs.

import base64
import fcntl
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from collections import Counter
from datetime import datetime
from pathlib import Path

rendered = Path("/root/homelab-rendered/src")
sys.path.insert(0, str(rendered / "base"))
import ntfy  # noqa: E402

node =socket.gethostname().split(".")[0]
script = rendered / "base/podman/image_updater.py"
var = Path("/var/lib/image_updater")
# state/<container>: "<remote digest> <outcome>" of the digest handled last;
# state/<container>.blocked: when the scan gate first blocked it
state = var / "state"
staging = var / "staging"
# accepted/<container>: digests `accept` passed, one per line
accepted = var / "accepted"
metrics = Path("/var/lib/node_exporter/textfile_collector/image_updater.prom")
trivy_cache = "/var/cache/trivy"
os.environ["PATH"] = "/usr/sbin:/usr/bin:/sbin:/bin"

# images: {service, container, image, upstream | build}, in update order. deadline_s: no
# image is started after this many seconds, so the run stays inside its 30-minute slot
# (image_updater.timer); what's left runs the next night. The notification path runs on
# secsvcs, its slot is last, and nothing has to fit after it.
nodes = {
  "homesvcs": {
    "images": [
      {"container": "traefik", "image": "localhost/library/traefik:v3.7", "service": "traefik", "upstream": "docker.io/library/traefik:v3.7"},
      {"container": "crowdsec_appsec", "image": "localhost/crowdsecurity/crowdsec:latest", "service": "crowdsec_appsec", "upstream": "docker.io/crowdsecurity/crowdsec:latest"},
      {"container": "vmagent", "image": "localhost/victoriametrics/vmagent:latest", "service": "vmagent", "upstream": "docker.io/victoriametrics/vmagent:latest"},
      {"container": "mosquitto", "image": "localhost/library/eclipse-mosquitto:latest", "service": "mosquitto", "upstream": "docker.io/library/eclipse-mosquitto:latest"},
      {"container": "zigbee2mqtt", "image": "localhost/koenkk/zigbee2mqtt:latest", "service": "zigbee2mqtt", "upstream": "ghcr.io/koenkk/zigbee2mqtt:latest"},
      {"container": "home_assistant", "image": "localhost/homeassistant/home-assistant:2026.10", "service": "home_assistant", "upstream": "docker.io/homeassistant/home-assistant:2026.10"},
      {"container": "fluentbit", "image": "localhost/fluent/fluent-bit:5.1", "service": "fluentbit", "upstream": "docker.io/fluent/fluent-bit:5.1"},
    ],
    # Container subnets are local to each node, so ntfy is reached through Traefik.
    "ntfy_url": "https://push.janedoe.com/alert",
    "deadline_s": 1500,
    "boot_delay_s": 0,
  },
  "secsvcs": {
    "images": [
      {"container": "postgres", "image": "localhost/library/postgres:18-alpine", "service": "postgres", "upstream": "docker.io/library/postgres:18-alpine"},
      {"container": "lldap", "image": "localhost/lldap/lldap:stable", "service": "lldap", "upstream": "docker.io/lldap/lldap:stable"},
      {"container": "authelia", "image": "localhost/authelia/authelia:4.39", "service": "authelia", "upstream": "docker.io/authelia/authelia:4.39"},
      {"container": "victorialogs", "image": "localhost/victoriametrics/victoria-logs:latest", "service": "victorialogs", "upstream": "docker.io/victoriametrics/victoria-logs:latest"},
      {"container": "gatus", "image": "localhost/twinproduction/gatus:latest", "service": "gatus", "upstream": "docker.io/twinproduction/gatus:latest"},
      {"container": "grafana", "image": "localhost/grafana/grafana-oss:latest", "service": "grafana", "upstream": "docker.io/grafana/grafana-oss:latest"},
      {"container": "vaultwarden", "image": "localhost/vaultwarden/server:latest", "service": "vaultwarden", "upstream": "docker.io/vaultwarden/server:latest"},
      {"container": "ntfy_idp_push", "image": "localhost/babraham123/ntfy-idp-push:0.3", "service": "ntfy_idp_push", "upstream": "ghcr.io/babraham123/ntfy-idp-push:0.3"},
      {"container": "olive_tin", "image": "localhost/jamesread/olivetin:latest-3k", "service": "olive_tin", "upstream": "docker.io/jamesread/olivetin:latest-3k"},
      {"container": "crowdsec", "image": "localhost/crowdsecurity/crowdsec:latest", "service": "crowdsec", "upstream": "docker.io/crowdsecurity/crowdsec:latest"},
      {"container": "crowdsec_appsec", "image": "localhost/crowdsecurity/crowdsec:latest", "service": "crowdsec_appsec", "upstream": "docker.io/crowdsecurity/crowdsec:latest"},
      {"container": "fluentbit", "image": "localhost/fluent/fluent-bit:5.1", "service": "fluentbit", "upstream": "docker.io/fluent/fluent-bit:5.1"},
      {"container": "traefik", "image": "localhost/library/traefik:v3.7", "service": "traefik", "upstream": "docker.io/library/traefik:v3.7"},
      {"container": "victoriametrics", "image": "localhost/victoriametrics/victoria-metrics:latest", "service": "victoriametrics", "upstream": "docker.io/victoriametrics/victoria-metrics:latest"},
      {"container": "vmalert", "image": "localhost/victoriametrics/vmalert:latest", "service": "vmalert", "upstream": "docker.io/victoriametrics/vmalert:latest"},
      {"container": "alertmanager", "image": "localhost/prom/alertmanager:latest", "service": "alertmanager", "upstream": "docker.io/prom/alertmanager:latest"},
      {"container": "ntfy-alertmanager", "image": "localhost/xenrox/ntfy-alertmanager:latest", "service": "ntfy-alertmanager", "upstream": "docker.io/xenrox/ntfy-alertmanager:latest"},
      {"container": "ntfy", "image": "localhost/binwiederhier/ntfy:latest", "service": "ntfy", "upstream": "docker.io/binwiederhier/ntfy:latest"},
    ],
    # Straight to the container: no DNS, Traefik or TLS between this script and ntfy
    # while their images update. IP: ntfy.container.
    "ntfy_url": "http://10.10.0.13:2586/alert",
    "deadline_s": 0,
    # A catch-up run after a pve1 reboot waits for ntfy and the rest to settle.
    "boot_delay_s": 900,
  },
  "vpnsvcs": {
    "images": [
      {"container": "fluentbit", "image": "localhost/fluent/fluent-bit:5.1", "service": "fluentbit", "upstream": "docker.io/fluent/fluent-bit:5.1"},
      {"container": "vmagent", "image": "localhost/victoriametrics/vmagent:latest", "service": "vmagent", "upstream": "docker.io/victoriametrics/vmagent:latest"},
      {"build": "geoip_generator", "container": "geoip_generator", "image": "localhost/geoip_generator:latest", "service": "geoip_generator"},
    ],
    # Container subnets are local to each node, so ntfy is reached through Traefik.
    "ntfy_url": "https://push.janedoe.com/alert",
    "deadline_s": 1500,
    "boot_delay_s": 0,
  },
  "websvcs": {
    "images": [
      {"container": "traefik", "image": "localhost/library/traefik:v3.7", "service": "traefik", "upstream": "docker.io/library/traefik:v3.7"},
      {"container": "crowdsec_appsec", "image": "localhost/crowdsecurity/crowdsec:latest", "service": "crowdsec_appsec", "upstream": "docker.io/crowdsecurity/crowdsec:latest"},
      {"container": "vmagent", "image": "localhost/victoriametrics/vmagent:latest", "service": "vmagent", "upstream": "docker.io/victoriametrics/vmagent:latest"},
      {"container": "nginx", "image": "localhost/library/nginx:stable", "service": "nginx", "upstream": "docker.io/library/nginx:stable"},
      {"container": "homepage", "image": "localhost/gethomepage/homepage:latest", "service": "homepage", "upstream": "ghcr.io/gethomepage/homepage:latest"},
      {"container": "isso", "image": "localhost/isso-comments/isso:release", "service": "isso", "upstream": "ghcr.io/isso-comments/isso:release"},
      {"container": "guacamole", "image": "localhost/guacamole/guacamole:1.6.0", "service": "guacamole", "upstream": "docker.io/guacamole/guacamole:1.6.0"},
      {"container": "guacd", "image": "localhost/guacamole/guacd:1.6.0", "service": "guacd", "upstream": "docker.io/guacamole/guacd:1.6.0"},
      {"build": "finance_exporter", "container": "finance_exporter", "image": "localhost/finance_exporter:latest", "service": "finance_exporter"},
      {"container": "fluentbit", "image": "localhost/fluent/fluent-bit:5.1", "service": "fluentbit", "upstream": "docker.io/fluent/fluent-bit:5.1"},
      {"container": "copyparty", "image": "localhost/copyparty/ac:latest", "service": "copyparty", "upstream": "docker.io/copyparty/ac:latest"},
      {"container": "linkding", "image": "localhost/sissbruecker/linkding:latest-plus", "service": "linkding", "upstream": "docker.io/sissbruecker/linkding:latest-plus"},
      {"container": "readeck", "image": "localhost/readeck/readeck:latest", "service": "readeck", "upstream": "codeberg.org/readeck/readeck:latest"},
      {"container": "storyteller", "image": "localhost/storyteller-platform/storyteller:web-v2", "service": "storyteller", "upstream": "registry.gitlab.com/storyteller-platform/storyteller:web-v2"},
      {"build": "calliope", "container": "calliope", "image": "localhost/calliope:latest", "service": "calliope"},
      {"build": "bookmark_handoff", "container": "bookmark_handoff", "image": "localhost/bookmark_handoff:latest", "service": "bookmark_handoff"},
    ],
    # Container subnets are local to each node, so ntfy is reached through Traefik.
    "ntfy_url": "https://push.janedoe.com/alert",
    "deadline_s": 1500,
    "boot_delay_s": 0,
  },
}


class Fatal(Exception):
  """die: ends the run, or the one image's attempt it was raised in."""


class Result(Exception):
  """Ends an image's attempt with its outcome: unchanged, pass (dry run), loaded,
  current, updated, failed, blocked or error."""

  def __init__(self, outcome, message=""):
    super().__init__(outcome)
    self.outcome, self.message = outcome, message


def log(message, stream=sys.stdout):
  print(f"{datetime.now().astimezone().isoformat(timespec='seconds')} {message}", file=stream, flush=True)


def warn(message):
  log(f"warning: {message}", sys.stderr)


def die(message):
  raise Fatal(message)


def run(*cmd, check=True, capture=False, **kwargs):
  """Runs cmd, its output to the journal unless captured; raises on failure if check."""
  return subprocess.run([str(c) for c in cmd], check=check, text=True,
                        stdout=subprocess.PIPE if capture else None, **kwargs)


def ok(*cmd):
  return run(*cmd, check=False, stderr=subprocess.DEVNULL).returncode == 0


def secret(name):
  value = run(rendered / "base/podman/get_secret.sh", name, capture=True).stdout.rstrip("\n")
  return "" if value == "null" else value


def notify(priority, title, message):
  # A person running install or accept is waiting; only the timer may be up before ntfy is
  attempts = 9 if mode == "run" else 1
  if not ntfy.notify(cfg["ntfy_url"], secret("ntfy_alert_token"), priority, f"{node}: {title}",
                     message, "package", attempts):
    warn(f"ntfy post failed: {title}")


# Docker Hub's anonymous pull limit is per IP, shared by every VM behind the router.
def registry_auth():
  user, token = secret("docker_hub_username"), secret("docker_hub_token")
  if not user or not token:
    warn("no Docker Hub credentials in the secrets file; pulling anonymously")
    return []
  path = tmp / "auth.json"
  auth = base64.b64encode(f"{user}:{token}".encode()).decode()
  path.touch(mode=0o600)
  path.write_text(json.dumps({"auths": {"docker.io": {"auth": auth}}}))
  return ["--authfile", path]


# A scan never runs against a stale database: the caller fails when this does.
def trivy_refresh():
  return (ok("trivy", "image", "--quiet", "--cache-dir", trivy_cache, "--download-db-only")
          and ok("trivy", "image", "--quiet", "--cache-dir", trivy_cache, "--download-java-db-only"))


def scan(service, source, report):
  """Exit 0 passes, 3 has findings, anything else is an error."""
  ignore = rendered / "services" / service / ".trivyignore"
  return run("trivy", "image", "--quiet", "--cache-dir", trivy_cache, "--cache-backend", "memory",
             "--skip-db-update", "--skip-java-db-update", "--scanners", "vuln",
             "--severity", "HIGH,CRITICAL", "--ignore-unfixed", "--exit-code", "3",
             "--format", "json", "--output", report,
             *(["--ignorefile", ignore] if ignore.is_file() else []), "--input", source,
             check=False).returncode


def vulnerabilities(report):
  for result in json.loads(Path(report).read_text()).get("Results") or []:
    for v in result.get("Vulnerabilities") or []:
      yield result.get("Target"), v


def findings(report):
  for target, v in vulnerabilities(report):
    print(f"{v.get('Severity')} {v.get('VulnerabilityID')} {v.get('PkgName')} "
          f"{v.get('InstalledVersion')} -> {v.get('FixedVersion')} ({target})", flush=True)


def last_digest(container):
  try:
    return (state / container).read_text().split(" ")[0].strip()
  except FileNotFoundError:
    return ""


def record(container, key, outcome):
  """The digest isn't handled again until upstream moves."""
  (state / container).write_text(f"{key} {outcome}\n")
  (state / f"{container}.blocked").unlink(missing_ok=True)


def attempt(check, *args):
  """Runs one image's check and returns its outcome, or broken if it failed. One image's
  failure doesn't end the run. An error (a registry or release lookup that failed, before
  anything changed) is tried again twice, a minute apart, so a blip doesn't cost the night."""
  container = args[1]
  for try_ in range(3):
    try:
      check(*args)
      outcome = "broken"
      log(f"{container}: ended without an outcome")
    except Result as r:
      outcome = r.outcome
      if r.message:
        log(f"{container}: {r.message}")
    except Exception as e:
      outcome = "broken"
      log(f"error: {e}", sys.stderr)
    if outcome != "error" or try_ == 2:
      return outcome
    time.sleep(60)


def blocked(container, key, report):
  """The scan gate stopped KEY; the old image keeps running."""
  findings(report)
  if mode == "run":
    marker = state / f"{container}.blocked"
    if not marker.exists():
      marker.write_text(f"{int(time.time())}\n")
    days = (int(time.time()) - int(marker.read_text())) // 86400
    ids = sorted({v.get("VulnerabilityID") for _, v in vulnerabilities(report)})
    ids = ", ".join(ids[:10]) + (", …" if len(ids) > 10 else "")
    if days < 7:
      notify(3, f"{container} update blocked",
             f"{key} has fixable HIGH/CRITICAL CVEs: {ids}. The old image keeps running.")
    else:
      notify(5, f"{container} blocked for {days} days",
             f"{key} has fixable HIGH/CRITICAL CVEs: {ids}. To override after review, add them to "
             "src/services/<service>/.trivyignore with an exp: date, or ssh manualadmin@"
             f"{node} and run: sudo {script} accept {container}")
  elif mode == "install":
    log(f"after review, to override: sudo {script} accept {container} (as manualadmin), then install again")


def is_accepted(container, key):
  try:
    return key in (accepted / container).read_text().splitlines()
  except FileNotFoundError:
    return False


def gate(service, container, key, source):
  """Returns if the image at SOURCE passes the scan, else ends the attempt as blocked. KEY
  is the digest or versions `accept` would record."""
  if is_accepted(container, key):
    log(f"{container}: {key} was accepted; not gated")
    return
  report = tmp / f"{container}.json"
  rc = scan(service, source, report)
  if rc == 0:
    log(f"{container}: scan passed")
  elif rc == 3:
    blocked(container, key, report)
    raise Result("blocked", "blocked by the scan")
  else:
    die(f"trivy failed on {container} (exit {rc})")


def untagged(image):
  return image.rsplit(":", 1)[0]


def keep_rollback(image):
  """What IMAGE names now stays reachable as its :rollback."""
  if ok("podman", "image", "exists", image):
    run("podman", "tag", image, f"{untagged(image)}:rollback")


def auto_update_result(container):
  """What `podman auto-update` reports for CONTAINER's unit, "" if nothing. Exit codes
  aren't documented, so only the report counts."""
  out = run("podman", "auto-update", "--format", "json", check=False, capture=True).stdout
  for unit in json.loads(out or "[]") or []:
    if unit.get("Unit") == f"{container}.service":
      updated = unit.get("Updated")
      return str(updated).lower() if isinstance(updated, bool) else str(updated)
  return ""


def roll_out(container, image, key):
  """IMAGE names the new image now. Restarts the container on it, or puts the :rollback
  image back."""
  if mode == "install":
    record(container, key, "loaded")
    raise Result("loaded", f"loaded {key}")
  # Each call also acts on every other AutoUpdate=local container, which is why a failed
  # image is pointed back at :rollback below before the next one.
  updated = auto_update_result(container)
  if updated == "true":
    record(container, key, "updated")
    raise Result("updated", f"updated to {key}")
  if updated == "false":
    record(container, key, "current")
    raise Result("current", f"already running {key}")
  if updated == "":
    # Not running, or its quadlet doesn't use AutoUpdate=local
    record(container, key, "loaded")
    raise Result("loaded", f"loaded {key}; no running container uses it")
  if ok("podman", "image", "exists", f"{untagged(image)}:rollback"):
    run("podman", "tag", f"{untagged(image)}:rollback", image)
  if not ok("systemctl", "is-active", "--quiet", f"{container}.service"):
    ok("systemctl", "restart", f"{container}.service")
  record(container, key, "failed")
  notify(4, f"{container} update failed",
         f"{key} didn't start (auto-update: {updated}); back on the previous image. "
         "Not retried until upstream changes.")
  raise Result("failed", f"update failed ({updated}); rolled back")


def upstream_digest(upstream):
  out = run("skopeo", "inspect", "--no-tags", *auth, f"docker://{upstream}", capture=True).stdout
  return json.loads(out)["Digest"]


def download(upstream, digest, oci_dir):
  """By digest, so what's scanned is what the inspect saw even if the tag moves meanwhile."""
  shutil.rmtree(oci_dir, ignore_errors=True)
  run("skopeo", "copy", "--quiet", *auth, f"docker://{untagged(upstream)}@{digest}", f"oci:{oci_dir}")


def check_upstream(service, container, image, upstream):
  """One pulled image."""
  oci_dir = staging / container
  try:
    # Always remote against remote: a multi-arch tag's digest isn't the local image's.
    digest = upstream_digest(upstream)
  except (subprocess.CalledProcessError, ValueError, KeyError):
    raise Result("error", f"can't inspect {upstream}; trying again tomorrow")
  if last_digest(container) == digest and ok("podman", "image", "exists", image):
    raise Result("unchanged", f"unchanged at {digest}")
  log(f"{container}: {upstream} is at {digest}")
  try:
    download(upstream, digest, oci_dir)
  except subprocess.CalledProcessError:
    raise Result("error", f"can't download {upstream}; trying again tomorrow")
  gate(service, container, digest, oci_dir)
  if mode == "dry-run":
    raise Result("pass", f"would load {digest} as {image}")
  keep_rollback(image)
  run("skopeo", "copy", "--quiet", f"oci:{oci_dir}", f"containers-storage:{image}")
  roll_out(container, image, digest)


def build_versions(service):
  """build.sh's inputs as one key, the one `accept` records for a built image."""
  script = rendered / "services" / service / "build.sh"
  if not os.access(script, os.X_OK):
    die(f"{service}: no executable {script}")
  return ",".join(run(script, "versions", capture=True).stdout.split())


def build_candidate(service, name, archive):
  """Builds localhost/NAME:candidate into ARCHIVE and returns its image ID. Scanned from a
  file, so Trivy doesn't need the podman socket. Untagged before the gate, so a blocked
  build is only a dangling image the next prune removes."""
  run(rendered / "services" / service / "build.sh", "build", "candidate")
  run("podman", "save", "-o", archive, f"localhost/{name}:candidate")
  built_id = json.loads(run("podman", "image", "inspect", f"localhost/{name}:candidate",
                            capture=True).stdout)[0]["Id"]
  run("podman", "untag", f"localhost/{name}:candidate")
  return built_id


def check_build(service, container, image, name):
  """One image built here, ending like check_upstream. src/services/SERVICE/build.sh takes
  `versions` (print every input it builds from: commits, base image digests) and `build
  TAG` (build localhost/NAME:TAG from them). tools/check_rendered.py requires one for every
  built image, so nothing built here skips the scan gate."""
  archive = staging / f"{container}.tar"
  try:
    versions = build_versions(service)
  except subprocess.CalledProcessError:
    raise Result("error", f"can't resolve {name}'s build inputs; trying again tomorrow")
  if last_digest(container) == versions and ok("podman", "image", "exists", image):
    raise Result("unchanged", f"unchanged at {versions}")
  log(f"{container}: building {versions}")
  built_id = build_candidate(service, name, archive)
  gate(service, container, versions, archive)
  if mode == "dry-run":
    raise Result("pass", f"would tag {versions} as {image}")
  keep_rollback(image)
  run("podman", "tag", built_id, image)
  roll_out(container, image, versions)


def check(entry):
  """attempt's arguments for one inventory image."""
  if "upstream" in entry:
    return check_upstream, entry["service"], entry["container"], entry["image"], entry["upstream"]
  return check_build, entry["service"], entry["container"], entry["image"], entry["build"]


def wait_for_boot():
  """Every run waits for boot, inside the script: a timer firing during boot would
  otherwise hold boot open while its unit waits on it."""
  status = run("systemctl", "is-system-running", "--wait", check=False, capture=True).stdout.strip()
  if status == "degraded":
    failed = run("systemctl", "list-units", "--failed", "--plain", "--no-legend",
                 check=False, capture=True).stdout
    warn(f"system degraded, failed units: {' '.join(line.split()[0] for line in failed.splitlines() if line)}")
  elif status != "running":
    die(f"system is {status}")
  up = int(float(Path("/proc/uptime").read_text().split()[0]))
  if up < cfg["boot_delay_s"]:
    log(f"waiting {cfg['boot_delay_s'] - up}s after boot")
    time.sleep(cfg["boot_delay_s"] - up)


def write_metrics(clean, count):
  """Keeps the previous success timestamp when this run wasn't clean, so the age alert
  counts from the last good run."""
  name = "image_updater_last_success_timestamp_seconds"
  last = None
  if metrics.exists():
    last = next((line.split()[1] for line in metrics.read_text().splitlines()
                 if line.split()[:1] == [name]), None)
  if clean:
    last = int(time.time())
  lines = [f"# HELP {name} Unix time of the last image_updater run with no broken or erroring image.",
           f"# TYPE {name} gauge"]
  if last is not None:
    lines.append(f"{name} {last}")
  lines += ["# HELP image_updater_images Images in the last image_updater run, by result.",
            "# TYPE image_updater_images gauge"]
  # %-formatting: a doubled brace would be Jinja here.
  lines += ['image_updater_images{result="%s"} %d' % (r, n) for r, n in count.items()]
  lines += ["# HELP image_updater_blocked_days Days since the scan gate first blocked the container's update.",
            "# TYPE image_updater_blocked_days gauge"]
  for marker in sorted(state.glob("*.blocked")):
    days = (int(time.time()) - int(marker.read_text())) // 86400
    lines.append('image_updater_blocked_days{container="%s"} %d' % (marker.stem, days))
  metrics.parent.mkdir(parents=True, exist_ok=True)
  partial = metrics.with_name(f"{metrics.name}.tmp")
  partial.write_text("\n".join(lines) + "\n")
  partial.chmod(0o644)
  # node_exporter only reads *.prom, and the rename is atomic.
  partial.rename(metrics)


def finish(clean, count):
  """The end of a nightly run, whatever happened."""
  try:
    write_metrics(clean, count)
  except OSError as e:
    warn(f"writing metrics failed: {e}")
  sys.exit(0 if clean else 1)


def update_all():
  global auth
  dry = mode == "dry-run"
  count = Counter({k: 0 for k in ("checked", "updated", "blocked", "failed", "error", "broken", "deferred")})
  if not dry:
    wait_for_boot()
  auth = registry_auth()
  if not trivy_refresh():
    if dry:
      die("Trivy DB refresh failed")
    warn("Trivy DB refresh failed; nothing checked")
    notify(5, "Image updater broken", "Trivy DB refresh failed, so nothing was checked.")
    finish(False, count)
  started, broken = time.monotonic(), []
  for entry in cfg["images"]:
    container = entry["container"]
    if not Path(f"/etc/containers/systemd/{container}.container").is_file():
      continue
    if not dry and cfg["deadline_s"] and time.monotonic() - started > cfg["deadline_s"]:
      log(f"{container}: past the deadline, left for tomorrow")
      count["deferred"] += 1
      continue
    count["checked"] += 1
    outcome = attempt(*check(entry))
    if outcome in ("updated", "blocked", "failed"):
      count[outcome] += 1
    # An error that outlasted its retries is broken too: expired registry credentials
    # would otherwise stop every update without the stale alert ever firing.
    elif outcome in ("error", "broken"):
      count[outcome] += 1
      broken.append(container)
      warn(f"{container}: pipeline {outcome}")
  if dry:
    if broken:
      die(f"broken: {' '.join(broken)}")
    return
  if not ok("podman", "image", "prune", "-f"):
    warn("image prune failed")
  if broken:
    notify(5, "Image updater broken", f"Failed on: {' '.join(broken)}. See journalctl -u image_updater.")
    finish(False, count)
  finish(True, count)


def install_images(service):
  """Every image of SERVICE is loaded and passed the scan gate before its quadlet is
  copied, or the install stops here."""
  global auth
  ready = False
  for entry in cfg["images"]:
    if entry["service"] != service:
      continue
    if not ready:
      auth = registry_auth()
      if not trivy_refresh():
        die("Trivy DB refresh failed")
      ready = True
    outcome = attempt(*check(entry))
    if outcome == "blocked":
      die(f"{entry['container']}: blocked by the scan gate")
    if outcome not in ("unchanged", "loaded"):
      die(f"{entry['container']}: {outcome}")


def accept(container):
  """Passes the current upstream digest, or build inputs, through the scan gate."""
  global auth
  if os.environ.get("SUDO_USER") != "manualadmin":
    die("accept is for manualadmin, through sudo")
  entry = next((e for e in cfg["images"] if e["container"] == container), None)
  if entry is None:
    die(f"no image for container {container} on {node}")
  service = entry["service"]
  auth = registry_auth()
  if not trivy_refresh():
    die("Trivy DB refresh failed")
  report = tmp / f"{container}.json"
  if "upstream" in entry:
    key = upstream_digest(entry["upstream"])
    source = staging / container
    download(entry["upstream"], key, source)
  else:
    # The next run builds again, so what this passes is the inputs, not this image.
    try:
      key = build_versions(service)
    except subprocess.CalledProcessError:
      die(f"can't resolve {entry['build']}'s build inputs")
    source = staging / f"{container}.tar"
    log(f"{container}: building {key}")
    build_candidate(service, entry["build"], source)
  rc = scan(service, source, report)
  if rc == 0:
    log(f"{container}: {key} has no fixable HIGH/CRITICAL findings")
  elif rc == 3:
    findings(report)
  else:
    die(f"trivy failed (exit {rc})")
  with (accepted / container).open("a") as f:
    f.write(f"{key}\n")
  log(f"{container}: accepted {key}; the next run loads it")
  notify(3, f"{container} accepted", f"manualadmin accepted {key} past the scan gate.")


def main():
  global mode, tmp
  usage = f"usage: {sys.argv[0]} [--dry-run | install SERVICE | accept CONTAINER]"
  args = sys.argv[1:]
  if os.geteuid() != 0:
    die("must run as root")
  for path in (var, state, staging, accepted):
    path.mkdir(parents=True, exist_ok=True)
    path.chmod(0o700)
  lock = open("/run/image_updater.lock", "w")
  try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
  except BlockingIOError:
    die("another image_updater is running")
  tmp = Path(tempfile.mkdtemp())
  try:
    if not args:
      mode = "run"
      update_all()
    elif args == ["--dry-run"]:
      mode = "dry-run"
      update_all()
    elif len(args) == 2 and args[0] in ("install", "accept"):
      mode = args[0]
      (install_images if mode == "install" else accept)(args[1])
    else:
      die(usage)
  finally:
    shutil.rmtree(tmp, ignore_errors=True)
    for path in staging.iterdir():
      shutil.rmtree(path) if path.is_dir() else path.unlink()


if __name__ == "__main__":
  if node not in nodes:
    log(f"error: no image list for {node}", sys.stderr)
    sys.exit(1)
  cfg, mode, tmp, auth = nodes[node], None, None, []
  try:
    main()
  except (Fatal, subprocess.CalledProcessError) as e:
    log(f"error: {e}", sys.stderr)
    sys.exit(1)
