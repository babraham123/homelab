# 04. deploy_src.sh: collect per-host failures and exit non-zero

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 28

## Change

Rewrite the body of `tools/deploy_src.sh`:

```bash
hosts=(pve1 secsvcs homesvcs pve2 websvcs vpn router devtop)   # or read from vars.yml
failed=()
for h in "${hosts[@]}"; do
  tools/upload_src.sh "$h" "$project_dir" || failed+=("$h")
done
echo; echo "Skipped (power on and run manually): gaming"
if ((${#failed[@]})); then
  echo "FAILED: ${failed[*]}" >&2; exit 1
fi
echo "Deployed to all hosts"
```

Keep `rm -rf "$project_dir"` in a `trap ... EXIT` so a failure still cleans up.

## Host list from vars.yml (needs a maintainer decision)

`vars.yml` has no `nodes` key today: `vpn`, `router`, `secsvcs`, `websvcs`, `homesvcs`,
`gaming`, `devtop`, `pve1`, `pve2` are top-level keys next to `site`, `users`, `lan`,
`wifi`, so `yq keys` can't tell a node from a subnet. Proposed reshape (`vars.template.yml`
too):

```yaml
nodes:               # map order == deploy order (yq preserves it)
  pve1:     {ip: 192.168.4.10, subnet: 192.168.4, mask: 192.168.4.0/24}
  secsvcs:  {ip: 192.168.4.20, container_subnet: 10.10.0}
  homesvcs: {ip: 192.168.4.21, container_subnet: 10.12.0}
  pve2:     {ip: 192.168.2.10, subnet: 192.168.2, mask: 192.168.2.0/24}
  websvcs:  {ip: 192.168.2.20, container_subnet: 10.11.0}
  vpn:      {ip: 12.34.56.78}
  router:   {ip: 192.168.1.1}
  devtop:   {ip: 192.168.2.22}
  gaming:   {ip: 192.168.2.21, deploy: manual}   # skipped by deploy_src.sh
subnets:
  lan:  {subnet: 192.168.1, mask: 192.168.1.0/24}
  lan2: {subnet: 192.168.3, mask: 192.168.3.0/24}
vlans:
  wifi:  {trusted: ..., iot: ..., guest: ...}
  wired: {trusted: ..., iot: ...}
```

Then `hosts=($(yq '.nodes | to_entries | map(select(.value.deploy != "manual")) | .[].key' vars.yml))`,
and `render_src.sh`/`upload_src.sh` drop their own lists. Cost: every `{{ <node>.` and
`{{ lan.`/`{{ wifi.` reference in `src/` and `docs/` becomes `{{ nodes.<node>.` etc.
(156 occurrences in `src/` and `docs/` on 2026-09-26; one mechanical sed). restructure/01's `src/nodes.yml` should use
the same node keys, with a render-time check that the two key sets match.

Until decided, keep the array in the script; the other hardcoded list
(`render_src.sh`'s `parse_dispatcher.sh` calls) goes with restructure/01.

## Comments

- 2026-09-26: `yq '.nodes | keys'` in the original text was wrong; see the section above.
