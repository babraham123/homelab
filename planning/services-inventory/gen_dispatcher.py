import yaml, pathlib, re
from jinja2 import Environment, FileSystemLoader
here = pathlib.Path(".")
inv = yaml.safe_load((here/"services.yml").read_text())
env = Environment(loader=FileSystemLoader("templates"), keep_trailing_newline=True)
out = env.get_template("dispatcher_cases.j2").render(services=inv["services"], node=inv["node"])
pathlib.Path("rendered-dispatcher-cases.sh").write_text(out)

gen = set(re.findall(r"^  install_([a-z0-9_-]+)\)$", out, re.M)) - {"all_svcs"}
cur = set(re.findall(r"^  install_([a-z0-9_-]+)\)$",
      (here/"../../src/secsvcs/dispatcher.sh").read_text(), re.M)) - {"all_svcs"}
inst = set(re.findall(r"^  ([a-z0-9_-]+)\)$",
      (here/"../../src/secsvcs/install_svcs.sh").read_text(), re.M))

print("services in install_svcs.sh but MISSING from dispatcher.sh today:")
for s in sorted(inst - cur): print(f"   x {s}")
print("\ncovered by the generated dispatcher:")
for s in sorted(inst - cur): print(f"   + {s}  -> {'YES' if s in gen else 'NO'}")
print(f"\nin dispatcher today but not a service (stubs/host-level): {sorted(cur - inst)}")
