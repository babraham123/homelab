# 05. Rename test/ to probes/

Status: resolved Type: task Repo: homelab Source: user item 56

`git mv test probes`; update `docs/networking.md` (`test/mdns.js`), `.fdignore` if listed,
`docs/development.md`, and the header comments inside the moved files.

## Comments
- 2026-10-10: Renamed; references were in `docs/debugging.md` and `docs/networking.md`. Neither
  `.fdignore`, `docs/development.md` nor the files' own headers mentioned `test/`.
