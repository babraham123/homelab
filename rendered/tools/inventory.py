#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml>=6,<7"]
# ///
# Derives the lists the templates use from the node inventory (ADR 0006), one
# src/nodes/<node>/inventory.yml per node. tools/lib.sh's template_vars gathers them into
# the template data as `nodes:`, in node-name order, and adds what this derives as `inv:`.
# A uv script, like check_rendered.py, which imports it.
# Usage:
#   tools/inventory.py derive < DATA   DATA: vars.yml plus `nodes:`; prints `inv` as JSON
#   tools/inventory.py dirs NODE       the src/ paths upload_src.sh ships a debian node, one
#                                      per line; run from the repo root or a rendered copy
#
# Per node, all keys optional:
#   debian_services: src/base/debian/install_svcs.sh cases, dispatched as install_<name>
#   services:        src/nodes/<node>/install_svcs.sh cases, dispatched as install_<name>.
#                    Key order is install order. Per service, all optional:
#                      shared:      true moves its case to src/base/podman/install_svcs.sh,
#                                   the platform services every container VM runs
#                      ip:          its container's host number on the node's
#                                   container_subnet; the quadlet's IP= and every
#                                   reference to it use inv.addr[node][<service>]
#                      subdomain:   host its Traefik router answers on
#                      admin:       true makes Authelia require two_factor on the
#                                   subdomain from every network, LAN and VPN
#                                   included; the app still decides who may use it
#                      uptime:      Gatus endpoint name (keys its history); monitors
#                                   https://<subdomain>.<site.url><uptime_path>
#                      uptime_path: default /
#                      uptime_tier: 1 checks every 2 minutes instead of 10 (the
#                                   proxies, login, and what you'd open first)
#                      uptime_conditions: extra Gatus conditions, appended to the
#                                   anchor's (status, latency, cert expiry)
#                      uptime_oauth: false checks without the Authelia bearer token, for
#                                   a path its Traefik router serves without ForwardAuth
#                                   and the app itself rejects foreign tokens on
#                      upstream:    pulled image, full ref with registry host and
#                                   namespace (docker.io/library/nginx:stable); the
#                                   quadlet's Image= must be localhost/ + the ref
#                                   without its host
#                      build:       built image name; Image= must be localhost/<build>:latest
#                      update_last: true moves the image to the end of the update run
#                      dirs:        src/-relative dirs its case uses beyond base/;
#                                   default [services/<service>] if it exists.
#                                   upload_src.sh ships a debian node only base/,
#                                   its src/nodes/<node>/ and these (upload_dirs)
#                      containers:  {<quadlet name>: {ip, upstream | build, update_last}}, in
#                                   place of the keys above, when the case installs
#                                   other quadlets than <service>.container
#   install_all_svcs: true adds install_all_svcs, installing `services` in order
#   install_some_svcs: [names] adds install_some_svcs, installing just these, in `services`
#                    order, for a node where the rest are too disruptive to reinstall blindly
#   image_updater_slot: HH:MM its image_updater.timer runs, 30 minutes apart per node
#   image_updater_java_db: false skips Trivy's Java DB, for nodes whose images hold no jars
#   commands:        other dispatcher cases, in order. Either
#                      {name, script}: runs `sudo <script> <name>`; script is under src/;
#                                      `sudo: false` drops the sudo
#                      {name, run}:    runs these lines verbatim
#                    pve1_file_transfer: true marks a command that moves files to or from
#                    pve1, so its case answers only pve1's certificate
#   triggers:        gaming only: Dispatcher.ps1 allowlist
#
# Derived, read by templates as inv.<name>; [node] means keyed by node:
#   dispatch[node]:   dispatcher cases in case order, [{name, run: [line, ...],
#                     pve1_file_transfer}]
#   cases[node]:      those cases as dispatcher.sh `case` text
#   buttons[node]:    case names OliveTin gets a button for: the non-pve1_file_transfer ones
#   nodes_with[case]: nodes whose dispatcher has that case, in node-name order; how
#                     scripts find e.g. the backup, install_ssh_ca or copy_acme_certs nodes
#   debian_nodes:     nodes whose install_dispatcher is src/base/debian/commands.sh's, so
#                     they share src/base/debian/dispatcher.sh and sudoers
#   sudo_cmds[node]:  sorted commands the dispatcher runs with sudo (sudoers)
#   subdomains[node]: sorted subdomains its Traefik serves (Unbound, HAProxy)
#   admin_subdomains: sorted subdomains of the admin services, all nodes (Authelia)
#   uptime:           Gatus internal endpoints, [{name, node, url, tier, conditions, oauth}]
#   images[node]:     container images in update order (install order, update_last
#                     entries last), [{service, dir, container, image, upstream | build}];
#                     dir: the service's first `dirs` entry, default services/<service>,
#                     where its .trivyignore and build.sh live
#   shared[node]:     its shared services, in install order
#   addr[node]:       {<quadlet name>: its container's IP address} for the containers with
#                     an ip; vpnsvcs's vmagent is inv.addr.vpnsvcs.vmagent
#   host_vars[node]:  {node, services, addr} for each node with a container_subnet in
#                     vars.yml: what src/base/podman/render_host.sh gives the second pass,
#                     where addr is addr[node]

import json
import sys
from pathlib import Path

import yaml

RENDERED_SRC = "/root/homelab-rendered/src/"
SHARED_SCRIPT = "base/podman/install_svcs.sh"
DEBIAN_DISPATCHER = "base/debian/commands.sh"


def services(spec):
  return {name: svc or {} for name, svc in (spec.get("services") or {}).items()}


def containers(spec):
  """(service name, service, quadlet name, its facts) per container, in install order."""
  for name, svc in services(spec).items():
    for container, facts in (svc.get("containers") or {name: svc}).items():
      yield name, svc, container, facts or {}


def is_debian(spec):
  return any(cmd["name"] == "install_dispatcher" and cmd.get("script") == DEBIAN_DISPATCHER
             for cmd in spec.get("commands", []))


def script_path(node, script):
  """Where a src/-relative script is on the node."""
  # upload_src.sh ships only src/nodes/router to the router, as /root/router-src
  if node == "router":
    return script.replace("nodes/router/", "/root/router-src/", 1)
  return RENDERED_SRC + script


def case(name, run, pve1_file_transfer=False):
  return {"name": name, "run": run, "pve1_file_transfer": pve1_file_transfer}


def dispatch(node, spec):
  def sudo(script, arg):
    return f"sudo {script_path(node, script)} {arg}"

  cases = [case(f"install_{svc}", [sudo("base/debian/install_svcs.sh", svc)])
           for svc in spec.get("debian_services", [])]
  install = {name: sudo(SHARED_SCRIPT if svc.get("shared") else f"nodes/{node}/install_svcs.sh", name)
             for name, svc in services(spec).items()}
  cases += [case(f"install_{name}", [line]) for name, line in install.items()]
  if spec.get("install_all_svcs"):
    cases.append(case("install_all_svcs", list(install.values())))
  some = spec.get("install_some_svcs")
  if some:
    unknown = set(some) - set(install)
    if unknown:
      sys.exit(f"{node}: install_some_svcs names unknown services {sorted(unknown)}")
    cases.append(case("install_some_svcs", [line for name, line in install.items() if name in some]))
  for cmd in spec.get("commands", []):
    if "run" in cmd:
      run = cmd["run"]
    else:
      run = [("sudo " if cmd.get("sudo", True) else "") + f"{script_path(node, cmd['script'])} {cmd['name']}"]
    cases.append(case(cmd["name"], run, cmd.get("pve1_file_transfer", False)))
  cases += [case(trigger, []) for trigger in spec.get("triggers", [])]
  return cases


def case_text(cases):
  lines = []
  for c in cases:
    lines.append(f"  {c['name']})")
    if c["pve1_file_transfer"]:
      lines.append("    require_pve1")
    lines += [f"    {line}" for line in c["run"]]
    lines.append("    ;;")
  return "\n".join(lines)


def sudo_cmds(cases):
  return sorted({line.removeprefix("sudo ") for c in cases for line in c["run"] if line.startswith("sudo ")})


def uptime(node, spec, site_url):
  return [{"name": svc["uptime"], "node": node,
           "url": f"https://{svc['subdomain']}.{site_url}{svc.get('uptime_path', '/')}",
           "tier": svc.get("uptime_tier", 2),
           "conditions": svc.get("uptime_conditions", []),
           "oauth": svc.get("uptime_oauth", True)}
          for svc in services(spec).values() if "uptime" in svc]


def images(spec):
  first, last = [], []
  for name, svc, container, facts in containers(spec):
    if "upstream" in facts:
      image = {"upstream": facts["upstream"], "image": "localhost/" + facts["upstream"].split("/", 1)[-1]}
    elif "build" in facts:
      image = {"build": facts["build"], "image": f"localhost/{facts['build']}:latest"}
    else:
      continue
    entry = {"service": name, "container": container,
             "dir": svc.get("dirs", [f"services/{name}"])[0], **image}
    (last if facts.get("update_last") else first).append(entry)
  return first + last


def addr(node, spec, node_vars):
  ips = {container: facts["ip"] for _, _, container, facts in containers(spec) if "ip" in facts}
  if ips and "container_subnet" not in node_vars:
    sys.exit(f"error: src/nodes/{node}/inventory.yml: containers have an ip, "
             f"but vars.yml has no {node}.container_subnet")
  return {container: f"{node_vars['container_subnet']}.{ip}" for container, ip in ips.items()}


def derive(data):
  nodes = {node: spec or {} for node, spec in data["nodes"].items()}
  node_vars = {node: data.get(node) or {} for node in nodes}
  cases = {node: dispatch(node, spec) for node, spec in nodes.items()}
  nodes_with = {}
  for node, node_cases in cases.items():
    for c in node_cases:
      nodes_with.setdefault(c["name"], []).append(node)
  addrs = {node: addr(node, spec, node_vars[node]) for node, spec in nodes.items()}
  return {
    "dispatch": cases,
    "cases": {node: case_text(c) for node, c in cases.items()},
    "buttons": {node: [c["name"] for c in node_cases if not c["pve1_file_transfer"]]
                for node, node_cases in cases.items()},
    "nodes_with": nodes_with,
    "debian_nodes": [node for node, spec in nodes.items() if is_debian(spec)],
    "sudo_cmds": {node: sudo_cmds(c) for node, c in cases.items()},
    "subdomains": {node: sorted(svc["subdomain"] for svc in services(spec).values() if "subdomain" in svc)
                   for node, spec in nodes.items()},
    "admin_subdomains": sorted(svc["subdomain"] for spec in nodes.values()
                               for svc in services(spec).values() if svc.get("admin")),
    "uptime": [u for node, spec in nodes.items() for u in uptime(node, spec, data["site"]["url"])],
    "images": {node: images(spec) for node, spec in nodes.items()},
    "shared": {node: [name for name, svc in services(spec).items() if svc.get("shared")]
               for node, spec in nodes.items()},
    "addr": addrs,
    "host_vars": {node: {"node": node, "services": services(spec), "addr": addrs[node]}
                  for node, spec in nodes.items() if "container_subnet" in node_vars[node]},
  }


def upload_dirs(node, spec):
  """The src/ paths upload_src.sh ships a debian node, in the same tree shape: all of base/,
  its nodes/<node>/ and each service's `dirs`, default services/<service> if it exists.
  None for other nodes, the router and gaming VM, which upload_src.sh handles on their own.
  Relative to the current dir, the repo root or a rendered copy."""
  if not is_debian(spec):
    return []
  paths = {"base", f"nodes/{node}"}
  for name, svc in services(spec).items():
    if "dirs" not in svc:
      if Path("src/services", name).is_dir():
        paths.add(f"services/{name}")
      continue
    for path in svc["dirs"]:
      if not Path("src", path).exists():
        raise ValueError(f"src/{path} doesn't exist")
      paths.add(path)
  return sorted(paths)


def main():
  match sys.argv[1:]:
    case ["derive"]:
      print(json.dumps(derive(yaml.safe_load(sys.stdin))))
    case ["dirs", node]:
      inventory = Path(f"src/nodes/{node}/inventory.yml")
      if not inventory.is_file():
        sys.exit(f"error: {inventory} doesn't exist")
      try:
        paths = upload_dirs(node, yaml.safe_load(inventory.read_text()) or {})
      except ValueError as e:
        sys.exit(f"error: {inventory}: {e}")
      for path in paths:
        print(path)
    case _:
      sys.exit("usage: tools/inventory.py derive < DATA | tools/inventory.py dirs NODE")


if __name__ == "__main__":
  main()
