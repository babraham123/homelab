#!/usr/bin/env python3
"""Validate a node inventory and render its generated outputs.

Usage: validate.py services.yml [--render routes]
"""
import sys, json, pathlib, collections
import yaml, jsonschema
from jinja2 import Environment, FileSystemLoader

here = pathlib.Path(__file__).parent
inv = yaml.safe_load((here / "services.yml").read_text())
schema = json.loads((here / "services.schema.json").read_text())

errs = []

# 1. Schema
v = jsonschema.Draft202012Validator(schema)
for e in sorted(v.iter_errors(inv), key=lambda e: list(e.path)):
    errs.append(f"schema: {'/'.join(map(str, e.path)) or '<root>'}: {e.message}")

svcs = inv["services"]

# 2. Container IP uniqueness (replaces the grep|sort|uniq -d check in render_src.sh)
ips = collections.Counter(s["ip"] for s in svcs.values() if "ip" in s)
for ip, n in ips.items():
    if n > 1:
        owners = [k for k, s in svcs.items() if s.get("ip") == ip]
        errs.append(f"duplicate container IP .{ip}: {', '.join(owners)}")

# 3. Subdomain uniqueness across the node
subs = collections.Counter(s["subdomain"] for s in svcs.values() if "subdomain" in s)
for sub, n in subs.items():
    if n > 1:
        errs.append(f"duplicate subdomain {sub}")

# 4. requires: targets exist, and order respects the dependency
for name, s in svcs.items():
    for dep in s.get("requires", []):
        if dep not in svcs:
            errs.append(f"{name}: requires unknown service '{dep}'")
        elif svcs[dep]["order"] >= s["order"]:
            errs.append(f"{name} (order {s['order']}) requires {dep} (order {svcs[dep]['order']}): "
                        f"dependency must install first")

# 5. Every secret has a real owner; every provides_postgres secret is declared
declared = set(inv.get("secrets", {}))
for sname, sec in inv.get("secrets", {}).items():
    if sec["owner"] not in svcs and "remote" not in sec:
        errs.append(f"secret {sname}: owner '{sec['owner']}' is not a service on this node "
                    f"and has no 'remote:' marker")
for name, s in svcs.items():
    for pg in s.get("provides_postgres", []):
        if pg["secret"] not in declared:
            errs.append(f"{name}: postgres db '{pg['db']}' uses undeclared secret {pg['secret']}")

# 6. Unpinned images (warning, not an error)
warns = [f"unpinned image: {n} -> {s['image']}"
         for n, s in svcs.items() if s["image"].endswith((":latest", ":stable", ":latest-3k"))]

# 7. Services exposed with no proxy auth — surfaced explicitly, never silent
open_routes = []
for name, s in svcs.items():
    if s.get("expose") == "none":
        continue
    routers = s.get("expose") or [{"id": "", "auth": s.get("auth", inv["defaults"]["auth"])}]
    for r in routers:
        auth = r.get("auth", s.get("auth", inv["defaults"]["auth"]))
        if auth == "none":
            open_routes.append(f"{name}{'-' + r['id'] if r.get('id') else ''}")

print(f"services: {len(svcs)}   secrets: {len(declared)}   routers: "
      f"{sum(len(s.get('expose') or [1]) for s in svcs.values() if s.get('expose') != 'none')}")
if warns:
    print("\nwarnings:")
    for w in warns: print(f"  ! {w}")
if open_routes:
    print("\nroutes with NO proxy auth (app-native auth only) — review each:")
    for o in open_routes: print(f"  ~ {o}")
if errs:
    print("\nERRORS:")
    for e in errs: print(f"  x {e}")
    sys.exit(1)
print("\nvalid")

if "--render" in sys.argv:
    env = Environment(loader=FileSystemLoader(here / "templates"),
                      trim_blocks=False, lstrip_blocks=False, keep_trailing_newline=True)
    out = env.get_template("routes.yml.j2").render(
        services=svcs, defaults=inv["defaults"], node=inv["node"],
        site={"url": "janedoe.com"})
    (here / "rendered-routes.yml").write_text(out)
    print(f"rendered -> {here/'rendered-routes.yml'}")
