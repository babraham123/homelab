# 06. Make the .DS_Store cleanup recursive

Status: ready-for-agent
Type: task
Repo: homelab
Source: review finding 30
Blocked by: 05

## Change

`tools/render_src.sh` (last lines) and `tools/render_docs.sh` use
`rm -f "$dir"/**/.DS_Store`; without `shopt -s globstar` bash treats `**` as `*`. Replace
with `find "$dir" -name .DS_Store -delete`. With the rsync exclude in script-fixes/05 this
becomes belt-and-braces, but `render_docs.sh` still needs it.

## Comments
