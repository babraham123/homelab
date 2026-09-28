# 06. Make the .DS_Store cleanup recursive

Status: resolved
Type: task
Repo: homelab
Source: review finding 30
Blocked by: 05

## Change

`tools/render_src.sh` (last lines) and `tools/render_docs.sh` use
`rm -f "$dir"/**/.DS_Store`; without `shopt -s globstar` bash treats `**` as `*`. Replace
with `find "$dir" -name .DS_Store -delete`. With the rsync exclude in script-fixes/05 this
becomes belt-and-braces, but `render_docs.sh` still needs it.

## Answer

- `tools/render_docs.sh`: `find "$project_dir" -name .DS_Store -delete`.
- `tools/render_src.sh`: `find . -name .DS_Store -delete`. It runs after `cd "$project_dir"`,
  so the old `"${project_dir}"/**` form also missed with a relative output path.
- Checked with `.DS_Store` files two levels deep in `docs/` and `src/`: none in either
  output, including a relative `render_src.sh` output path.

## Comments
