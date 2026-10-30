#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml>=6,<7"]
# ///
# Checks a rendered copy of the repo: YAML, JSON and markdown, then the
# node inventory (src/nodes/<node>/inventory.yml, ADR 0006) against the scripts, routes,
# quadlets and OliveTin buttons it describes. Called by render_src.sh; tests/ runs it
# against fixture trees. A uv script: `uv run` installs its dependencies, listed above.
# Usage:
#   tools/check_rendered.py /dir/with/rendered/copy /path/to/all_vars.yml
# all_vars.yml is the data file the copy was rendered with: vars.yml plus `nodes:` and
# `inv:` (tools/lib.sh template_vars).
# Reports every failure as "error: FILE: MESSAGE" and exits 1 if there was any.

import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

import yaml

# No __pycache__ next to the script, in the repo or the rendered copy
sys.dont_write_bytecode = True
from inventory import upload_dirs  # noqa: E402

# Traefik's fallback route: it serves hosts that have no DNS or SNI entry, so it may
# route more hosts than the inventory lists.
DEFAULT_ROUTE_NODE = "websvcs"


failed = False


def fail(file, message):
  global failed
  print(f"error: {file}: {message}", file=sys.stderr)
  failed = True


def warn(message):
  print(f"warning: {message}", file=sys.stderr)


def inventory(node):
  return f"src/nodes/{node}/inventory.yml"


SHARED_SCRIPT = "src/base/podman/install_svcs.sh"


def install_script(node, spec, svc):
  """The install_svcs.sh that holds a service's case."""
  return SHARED_SCRIPT if svc in spec["shared"] else f"src/nodes/{node}/install_svcs.sh"


def text_lines(path):
  """A file's lines, or none for a binary file (grep -I)."""
  data = Path(path).read_bytes()
  return [] if b"\0" in data else data.decode(errors="replace").splitlines()


def tree_lines(path):
  """Every line of every text file under path."""
  path = Path(path)
  if not path.exists():
    return []
  files = sorted(p for p in path.rglob("*") if p.is_file()) if path.is_dir() else [path]
  return [line for f in files for line in text_lines(f)]


def cases(path):
  """Case labels of a script's `case` blocks, or the first words a Python script's
  `match args` cases take (`case ["pause", *rest]:`)."""
  label = r'^\s+case \["([A-Za-z0-9_-]+)"' if path.endswith(".py") else r"^\s+([A-Za-z0-9_-]+)\).*$"
  return {m[1] for line in text_lines(path) if (m := re.match(label, line))}


def case_block(path, label):
  """The lines of a script's `label)` case, up to its `;;`."""
  block, inside = [], False
  for line in text_lines(path):
    if not inside:
      inside = line.split()[:1] == [f"{label})"]
    elif ";;" in line:
      break
    else:
      block.append(line)
  return block


def load_facts(all_vars):
  """Every inventory fact the checks use, from the data the copy was rendered with: the
  same lists tools/inventory.py derived for the templates."""
  data = yaml.safe_load(Path(all_vars).read_text())
  inv = data["inv"]
  nodes = {}
  for node, spec in data["nodes"].items():
    spec = spec or {}
    nodes[node] = {
      "inventory": spec,
      "services": list(spec.get("services") or {}),
      "shared": inv["shared"][node],
      "addr": inv["addr"][node],
      "image_updater_slot": spec.get("image_updater_slot"),
      "debian_services": spec.get("debian_services", []),
      "cases": inv["dispatch"][node],
      "subdomains": inv["subdomains"][node],
      "images": inv["images"][node],
    }
  return data["site"]["url"], nodes


def check_yaml():
  out = subprocess.run(["yamllint", "-f", "parsable", "-c", "lint.yaml", "."],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
  for line in out.splitlines():
    line = line.removeprefix("./")
    if not line:
      continue
    file = line.split(": ", 1)[0]
    if " [error] " in line:
      fail(file, line.split(": [error] ", 1)[1])
    elif " [warning] " in line:
      warn(f"{file}: {line.split(': [warning] ', 1)[1]}")
    else:
      fail("lint.yaml", f"yamllint: {line}")


def check_json():
  for path in sorted(Path(".").rglob("*.json")):
    text = path.read_text(errors="replace")
    if not text.strip():
      continue
    try:
      json.loads(text)
    except ValueError:
      fail(path, "invalid JSON")


# Rules in .markdownlint-cli2.yaml. Findings come on stderr as "FILE:LINE[:COL] error RULE
# DESCRIPTION"; stdout is only a banner.
def check_markdown():
  out = subprocess.run(["markdownlint-cli2", "**/*.md"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE, text=True).stderr
  for line in filter(None, out.splitlines()):
    fail(line.split(" ", 1)[0], line.split(" error ", 1)[-1])


# Containers on one node share its container subnet, whose .1 is the bridge gateway.
def check_container_addrs(nodes):
  for node, spec in nodes.items():
    by_addr = {}
    for container, addr in spec["addr"].items():
      by_addr.setdefault(addr, []).append(container)
    for addr, containers in sorted(by_addr.items()):
      if len(containers) > 1:
        fail(inventory(node), f"{' and '.join(containers)} have the same ip, {addr}")


# The image updater loads images under these names, so a quadlet whose Image= differs
# would never be updated. Its IP= is its addr from the inventory, which every reference
# to it uses; a second-pass quadlet gets the node's from render_host.sh.
def check_quadlets(nodes):
  for node, spec in nodes.items():
    for i in spec["images"]:
      svc, container, image = i["service"], i["container"], i["image"]
      script = install_script(node, spec, svc)
      if not os.path.isfile(script):
        continue  # check_dispatch_scripts reports it
      where = f"({inventory(node)} services.{svc})"
      pattern = rf"[A-Za-z0-9_./-]+/{re.escape(container)}\.container"
      quadlet = next((m[0] for line in case_block(script, svc) if (m := re.search(pattern, line))), None)
      if not quadlet:
        fail(script, f"the {svc} case copies no {container}.container {where}")
        continue
      # A *.container.j2.j2 source is still *.container.j2 until install time
      file = f"src/{quadlet}"
      if not os.path.isfile(file):
        file += ".j2"
      lines = text_lines(file) if os.path.isfile(file) else []
      actual = "\n".join(line.removeprefix("Image=") for line in lines if line.startswith("Image="))
      if actual != image:
        fail(file, f"Image={actual}, expected {image} {where}")
      ip = "\n".join(line.removeprefix("IP=") for line in lines if line.startswith("IP=")) or None
      expected = spec["addr"].get(container)
      if expected and file.endswith(".j2"):
        expected = f"{{{{ addr.{container} }}}}"
      if ip != expected:
        fail(file, f"IP={ip or ''}, expected {expected or 'no IP=, as there is no ip'} {where}")


# The image updater builds a built image only through its service's build.sh, so one
# without would never pass the scan gate.
def check_build_scripts(nodes):
  for node, spec in nodes.items():
    for i in spec["images"]:
      svc, script = i["service"], f"src/{i['dir']}/build.sh"
      if not i.get("upstream") and not os.path.isfile(script):
        fail(inventory(node), f"services.{svc}: built image {i['image']} has no {script}")


def script_file(script):
  """The tree path of a script a dispatcher line runs, or None if it isn't one of the repo's."""
  if script.startswith("/root/homelab-rendered/src/"):
    return "src/" + script.removeprefix("/root/homelab-rendered/src/")
  # upload_src.sh ships only src/nodes/router to the router, as /root/router-src
  if script.startswith("/root/router-src/"):
    return "src/nodes/router/" + script.removeprefix("/root/router-src/")
  return None


# Every repo script a dispatcher runs must exist and, when it is passed a name, have
# that case. This covers services, debian_services, commands[].script and the paths in
# commands[].run.
def check_dispatch_scripts(nodes):
  runs = sorted({(node, line.strip()) for node, spec in nodes.items()
                 for case in spec["cases"] for line in case["run"]})
  for node, line in runs:
    script, _, arg = line.removeprefix("sudo ").partition(" ")
    file = script_file(script)
    if file is None:
      continue
    if not os.path.isfile(file):
      fail(file, f"missing, but the {node} dispatcher runs it")
    elif arg and arg not in cases(file):
      fail(file, f"no {arg} case, but the {node} dispatcher runs it")


# The reverse of check_dispatch_scripts for install_svcs.sh: a case the inventory
# doesn't list would have no dispatcher case, sudo grant or OliveTin button. A node's
# own script holds its services that aren't shared; the shared script, the services some
# node marks shared.
def check_install_cases(nodes):
  for node, spec in nodes.items():
    file = f"src/nodes/{node}/install_svcs.sh"
    if not os.path.isfile(file):
      continue
    for svc in sorted(cases(file) - set(spec["services"])):
      fail(file, f"the {svc} case isn't in {inventory(node)} services")
    for svc in sorted(cases(file) & set(spec["shared"])):
      fail(file, f"the {svc} case is shared in {inventory(node)}, so {SHARED_SCRIPT} runs it")
  if os.path.isfile(SHARED_SCRIPT):
    shared = {svc for spec in nodes.values() for svc in spec["shared"]}
    for svc in sorted(cases(SHARED_SCRIPT) - shared):
      fail(SHARED_SCRIPT, f"the {svc} case isn't a shared service in any node's inventory")


# image_updater.timer runs at the node's slot; without one it would never run.
def check_image_updater_slots(nodes):
  slots = {}
  for node, spec in nodes.items():
    if "image_updater" not in spec["debian_services"]:
      continue
    slot = spec["image_updater_slot"]
    if slot is None:
      fail(inventory(node), "no image_updater_slot, but it runs image_updater")
    else:
      slots.setdefault(slot, []).append(inventory(node))
  for slot, files in sorted(slots.items()):
    if len(files) > 1:
      fail(" ".join(files), f"image_updater_slot {slot} is set for more than one node")


def check_unique_subdomains(nodes):
  counts = Counter(s for spec in nodes.values() for s in spec["subdomains"])
  for subdomain in sorted(s for s, n in counts.items() if n > 1):
    owners = sorted({inventory(node) for node, spec in nodes.items() if subdomain in spec["subdomains"]})
    fail(" ".join(owners), f"subdomain {subdomain} is listed more than once")


# The subdomain lists drive DNS and SNI routing and the uptime URLs, so each must be
# routed by its node's Traefik, and every host Traefik routes must be listed, except
# on the default route.
def check_routes(site, nodes):
  for node, spec in nodes.items():
    routes = f"src/nodes/{node}/traefik/routes.yml"
    if not os.path.isfile(routes):
      continue
    routers = ((yaml.safe_load(Path(routes).read_text()) or {}).get("http") or {}).get("routers") or {}
    hosts = {h for r in routers.values() for h in re.findall(r"Host\(`([^`]+)`\)", str(r.get("rule", "")))}
    routed = {h.removesuffix(f".{site}") for h in hosts if h.endswith(f".{site}")}
    listed = set(spec["subdomains"])
    for subdomain in sorted(listed - routed):
      fail(routes, f"no Host() rule for {subdomain}, listed in {inventory(node)} services")
    if node == DEFAULT_ROUTE_NODE:
      continue
    for subdomain in sorted(routed - listed):
      fail(inventory(node), f"no service has subdomain {subdomain}, which {routes} routes")


def shells(value):
  """Every `shell` value of every mapping in a parsed YAML document."""
  if isinstance(value, dict):
    if "shell" in value:
      yield str(value["shell"])
    for v in value.values():
      yield from shells(v)
  elif isinstance(value, list):
    for v in value:
      yield from shells(v)


# Every ungated dispatcher case gets an OliveTin button; every `ssh autoadmin@NODE CASE`
# OliveTin runs, chained or not, names a real case that OliveTin's own key may run.
def check_olive_tin(nodes):
  config = "src/services/olive_tin/config.yaml"
  if not os.path.isfile(config):
    fail(config, "missing")
    return
  cases_of = {(node, c["name"]): c for node, spec in nodes.items() for c in spec["cases"]}
  buttons = {key for key, c in cases_of.items() if not c["pve1_file_transfer"]}
  referenced = {(m[1], m[2]) for shell in shells(yaml.safe_load(Path(config).read_text()))
                for line in shell.splitlines()
                for m in re.finditer(r"ssh autoadmin@([^ ]+) ([^ &;|]+)", line)}
  for node, name in sorted(buttons - referenced):
    fail(config, f"no button runs {node} dispatcher case {name}")
  for node, name in sorted(referenced - buttons):
    if (node, name) in cases_of:
      fail(config, f"runs ssh autoadmin@{node} {name}, a pve1 file transfer only pve1 may run")
    else:
      fail(config, f"runs ssh autoadmin@{node} {name}, which isn't a {node} dispatcher case")


ANCHORED = r"(homelab-rendered/src/|\$\{?rendered\}?/|\.\./)"


def src_refs(lines, prefix):
  """The nodes/ and services/ paths in lines that follow the prefix regex, outside comments."""
  pattern = re.compile(prefix + r"(?P<ref>(?:nodes|services)/[A-Za-z0-9_.-]+)")
  return {m["ref"] for line in lines if not re.match(r"^\s*#", line)
          for m in pattern.finditer(line)}


# upload_src.sh ships a debian node all of base/ but only the node and service dirs
# upload_dirs lists, in the same tree shape, so every nodes/ and services/ path it uses
# must be among them. That is every absolute (/root/homelab-rendered/src/...,
# ${rendered}/...) or ../ path in its node and service dirs, plus the src/-relative paths
# in its node dir, dispatcher lines, debian_services cases and shared services' cases.
# base/ is skipped: its scripts serve every node and name other nodes' dirs only in what
# those nodes run, like the shared traefik install.
def check_upload_dirs(nodes):
  for node, spec in nodes.items():
    try:
      paths = upload_dirs(node, spec["inventory"])
    except ValueError as e:
      fail(inventory(node), e)
      continue
    if not paths:
      continue
    shipped = [line for path in paths if path != "base" for line in tree_lines(f"src/{path}")]
    own = (tree_lines(f"src/nodes/{node}")
           + [line for c in spec["cases"] for line in c["run"]]
           + [line for svc in spec["debian_services"]
              for line in case_block("src/base/debian/install_svcs.sh", svc)]
           + [line for svc in spec["shared"] for line in case_block(SHARED_SCRIPT, svc)])
    refs = src_refs(shipped, ANCHORED) | src_refs(own, rf"({ANCHORED}|^|[^A-Za-z0-9_./-])")
    for ref in sorted(refs):
      # Other paths that happen to match, like a container's /data/services/
      if os.path.exists(f"src/{ref}") and ref not in paths:
        fail(inventory(node),
             f"uses src/{ref}, which upload_src.sh doesn't ship to it; add it to a service's dirs")


def main():
  tree, all_vars = sys.argv[1], os.path.abspath(sys.argv[2])
  os.chdir(tree)
  site, nodes = load_facts(all_vars)
  check_yaml()
  check_json()
  check_markdown()
  check_container_addrs(nodes)
  check_quadlets(nodes)
  check_build_scripts(nodes)
  check_dispatch_scripts(nodes)
  check_install_cases(nodes)
  check_image_updater_slots(nodes)
  check_unique_subdomains(nodes)
  check_routes(site, nodes)
  check_olive_tin(nodes)
  check_upload_dirs(nodes)
  sys.exit(1 if failed else 0)


if __name__ == "__main__":
  main()
