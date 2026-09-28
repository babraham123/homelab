# 02. parse_images.sh, render wiring and the Image=/label check

Status: resolved
Type: task
Repo: homelab
Source: notes/image-updater-design.md "Image list and order", "Image references"
Blocked by: script-fixes/01

## Change

- `tools/parse_images.sh <node>`, called from `tools/render_src.sh` for secsvcs,
  homesvcs and websvcs:
  - read `case` entries of `src/<node>/install_svcs.sh` in file order (same order
    `gen_dispatch_cmds.sh` uses for `install_all_svcs`);
  - map each case to the `.container` files it copies;
  - read `homelab.upstream`, `homelab.build` and `homelab.update_last` labels;
  - move `update_last` entries to the end;
  - write `<node>_images` (list of `{container, image, upstream | build}`) to
    `all_vars.yml`.
  Match service names with `[a-zA-Z0-9_-]+`; `ntfy-alertmanager` is an `update_last`
  entry, which is why this waits on script-fixes/01.
- Render-time check next to the duplicate-IP check: for every quadlet with
  `homelab.upstream`, `Image=` must equal `localhost/` + the upstream ref without its
  registry host. Fail the render otherwise.
- Quadlets without labels yield an empty list; that is the expected state until 05.

## Acceptance

- With labels added to one test quadlet, `all_vars.yml` lists it in install order,
  `update_last` entries last.
- A mismatched `Image=` fails the render with the file and expected value.

## Answer

Done per the 2026-09-27 comment; there is no `tools/parse_images.sh`.

- `src/nodes.yml` service entries take `upstream:` (full ref with registry host and
  namespace), `build:` (image name), `update_last: true`, and `containers:
  {<quadlet>: {upstream | build, update_last}}` in place of those keys when a case installs
  other quadlets than `<service>.container` (archivebox → archivebox + novnc). Documented
  in the file's header.
- `src/nodes.jinja` exports `images[node]`: `[{service, container, image, upstream |
  build}]` in install order, `update_last` entries moved to the end. `image` is
  `localhost/` + the upstream ref without its host, or `localhost/<build>:latest`.
  Entries without `upstream`/`build` are skipped, so every list is empty today.
- `tools/render_src.sh`, next to the duplicate-IP check, fails the render when:
  - an `upstream` ref has no registry host and namespace;
  - the service's `install_svcs.sh` case copies no `<container>.container`;
  - that quadlet's `Image=` isn't the derived `image` (message names the rendered file,
    the actual and the expected value). `*.container.j2.j2` sources are checked as the
    rendered `*.container.j2`.
- Checked with temporary facts on websvcs nginx (`update_last`), archivebox
  (`containers:` archivebox + novnc build), piper (build) and secsvcs fluentbit (a
  `.j2.j2` quadlet): list came out archivebox, novnc, piper, nginx; each of the three
  failure cases failed with the message above; restoring the files renders cleanly with
  unchanged output.
- For 05: the facts go on `src/nodes.yml`, not quadlet `Label=`s; the quadlets only need
  `Image=localhost/…` and `AutoUpdate=local`.

## Comments

- restructure/01 replaces the other `parse_*` scripts with `src/nodes.yml`; if it lands
  first, derive the list from there instead of writing a new parser.
- 2026-09-27: restructure/01 landed. Don't write `tools/parse_images.sh`:
  `nodes.<node>.services` in `src/nodes.yml` is already in install order (the same order
  `install_all_svcs` uses). Put the image facts on the service entry (e.g. `upstream:` /
  `build:`, `update_last: true`, and `containers:` for services that install more than
  `<name>.container`, like archivebox → novnc) and derive `<node>_images` in
  `src/nodes.jinja`. The quadlet labels then aren't needed, and the `Image=` check
  compares quadlets against `nodes.yml`.
