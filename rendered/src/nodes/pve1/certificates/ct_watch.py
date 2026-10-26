#!/usr/bin/env python3
# Certificate Transparency watch: lists the unexpired certificates ctlogs.dev has indexed for
# the domain and its subdomains, and pushes an ntfy alert for any that Let's Encrypt didn't
# issue or that names a host missing from EXPECTED, i.e. one this homelab didn't ask for.
# Each certificate is pushed once; the journal lists every finding on every run. A new host
# outside the node inventories goes in EXPECTED. Standard library only.
# Usage:
#   /root/homelab-rendered/src/nodes/pve1/certificates/ct_watch.py

import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

rendered = Path("/root/homelab-rendered/src")
sys.path.insert(0, str(rendered / "base"))
import ntfy  # noqa: E402

DOMAIN = "janedoe.com"
# Every host with a certificate: the inventory subdomains, the apex (redirects to www), wifi
# (nginx on websvcs), the ACME-only pve1, pve2, pbs2 and router (websvcs' acme_routes.yml),
# and vpn (Headscale requests its own)
EXPECTED = {
    DOMAIN,
    "alert.janedoe.com",
    "archive.janedoe.com",
    "auth.janedoe.com",
    "books.janedoe.com",
    "command.janedoe.com",
    "comment.janedoe.com",
    "dash.janedoe.com",
    "files.janedoe.com",
    "graph.janedoe.com",
    "home.janedoe.com",
    "homeproxy.janedoe.com",
    "idp-push.janedoe.com",
    "ldap.janedoe.com",
    "logs.janedoe.com",
    "metrics.janedoe.com",
    "ntfy-alertmanager.janedoe.com",
    "pbs2.janedoe.com",
    "push.janedoe.com",
    "pve1.janedoe.com",
    "pve2.janedoe.com",
    "read.janedoe.com",
    "remote.janedoe.com",
    "router.janedoe.com",
    "secproxy.janedoe.com",
    "uptime.janedoe.com",
    "vault.janedoe.com",
    "vmalert.janedoe.com",
    "vpn.janedoe.com",
    "webproxy.janedoe.com",
    "wifi.janedoe.com",
    "www.janedoe.com",
    "zigbee.janedoe.com",
}
ISSUER = "Let's Encrypt"
API = f"https://api.ctlogs.dev/v1/subdomains/{DOMAIN}"
NTFY_URL = "https://push.janedoe.com/alert"
# Certificate ids already pushed, one per line
ALERTED = Path("/var/lib/ct_watch/alerted")
os.environ["PATH"] = "/usr/sbin:/usr/bin:/sbin:/bin"


def log(message, stream=sys.stdout):
  print(f"{datetime.now().astimezone().isoformat(timespec='seconds')} {message}", file=stream, flush=True)


def get(url):
  """The keyless API allows 100 requests an hour, one at a time; retries for 10 minutes."""
  # Cloudflare in front of the API refuses urllib's default User-Agent with a 403
  request = urllib.request.Request(url, headers={"User-Agent": "homelab-ct-watch"})
  for attempt in range(6):
    try:
      with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)
    except (OSError, ValueError) as error:
      log(f"warning: {url}: {error}", sys.stderr)
      if attempt < 5:
        time.sleep(120)
  sys.exit(f"ctlogs.dev unreachable: {url}")


def rows():
  """One row per certificate and name it matched; includes certificates expired within 90 days."""
  cursor = ""
  while True:
    page = get(f"{API}?after={cursor}" if cursor else API)
    yield from page["rows"]
    if not page["has_next"]:
      return
    cursor = page["next_cursor"]


def alert_token():
  # The alert token is a secsvcs secret; pve1 holds every host's secrets file.
  secrets = subprocess.run(["age", "-d", "-i", "/root/secrets/age.txt", "/root/secrets/secsvcs.yaml.age"],
                           check=True, stdout=subprocess.PIPE).stdout
  return subprocess.run(["yq", ".ntfy_alert_token"], input=secrets, check=True,
                        stdout=subprocess.PIPE).stdout.decode().strip()


now = datetime.now(timezone.utc)
findings = {}
for row in rows():
  name = row["match"].lower()
  if datetime.fromisoformat(row["not_after"]) <= now:
    continue
  if row["issuer"] != ISSUER or name not in EXPECTED:
    findings.setdefault(row["id"], (row, set()))[1].add(name)

if not findings:
  log(f"no unexpected certificates for {DOMAIN}")
  sys.exit(0)

lines = {cert: f"{row['issuer']}: {', '.join(sorted(names))} (from {row['not_before'][:10]}) "
             f"https://api.ctlogs.dev/v1/cert/{cert}"
         for cert, (row, names) in findings.items()}
log(f"unexpected certificates for {DOMAIN}:\n" + "\n".join(lines.values()))

alerted = set(ALERTED.read_text().split()) if ALERTED.exists() else set()
new = [cert for cert in lines if cert not in alerted]
if not new:
  log("all already pushed")
  sys.exit(0)
if not ntfy.notify(NTFY_URL, alert_token(), 4, f"Unexpected certificates for {DOMAIN}",
                   "\n".join(lines[cert] for cert in new), "warning"):
  sys.exit("ntfy post failed")
# Expired certificates drop out of the results, so only current findings are kept.
ALERTED.parent.mkdir(parents=True, exist_ok=True)
ALERTED.write_text("".join(f"{cert}\n" for cert in lines))
