"""Semantic diff: generated routes.yml vs the hand-written one (anchors resolved)."""
import yaml, re, pathlib, json
raw = pathlib.Path("../../src/secsvcs/traefik/routes.yml.j2").read_text()
raw = raw.replace("{{ site.url }}", "janedoe.com")
orig = yaml.safe_load(raw)          # PyYAML resolves the &service / <<: anchors
gen  = yaml.safe_load(pathlib.Path("rendered-routes.yml").read_text())

def norm(doc):
    out = {}
    for rname, r in (doc.get("http", {}).get("routers") or {}).items():
        out[rname] = {
            "rule": re.sub(r"\s+", " ", r["rule"]).strip(),
            "service": r["service"],
            "mw": list(r.get("middlewares") or []),
            "tls": r.get("tls"),
        }
    svc = {}
    for sname, s in (doc.get("http", {}).get("services") or {}).items():
        svc[sname] = s["loadBalancer"]["servers"][0]["url"]
    return out, svc

o_r, o_s = norm(orig); g_r, g_s = norm(gen)

print(f"routers  hand-written: {len(o_r)}   generated: {len(g_r)}")
print(f"services hand-written: {len(o_s)}   generated: {len(g_s)}\n")

for key, o, g, label in (("routers", o_r, g_r, "router"), ("services", o_s, g_s, "service")):
    only_o, only_g = sorted(set(o) - set(g)), sorted(set(g) - set(o))
    if only_o: print(f"  only hand-written {label}s: {only_o}")
    if only_g: print(f"  only generated {label}s:    {only_g}")

diffs = 0
for name in sorted(set(o_r) & set(g_r)):
    if o_r[name] != g_r[name]:
        diffs += 1
        print(f"\n  DIFF router '{name}'")
        for f in ("rule", "service", "mw", "tls"):
            if o_r[name][f] != g_r[name][f]:
                print(f"    {f}:\n      hand: {o_r[name][f]}\n      gen:  {g_r[name][f]}")
for name in sorted(set(o_s) & set(g_s)):
    if o_s[name] != g_s[name]:
        diffs += 1
        print(f"  DIFF service '{name}': hand={o_s[name]}  gen={g_s[name]}")

print(f"\n{len(set(o_r) & set(g_r))} shared routers compared, {diffs} differing")
