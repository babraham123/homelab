# 04. Rename guides to match node names

Status: ready-for-agent
Type: task
Repo: homelab
Source: user item 55

## Change

`git mv` in `docs/guides/`: `secure_services.md.j2` → `secsvcs.md.j2`,
`home_services.md.j2` → `homesvcs.md.j2`, `web_services.md.j2` → `websvcs.md.j2`,
`dev_desktop.md.j2` → `devtop.md.j2`. Update links in `docs/*.md`, `docs/adr/*.md`,
`README.md`, `CONTEXT.md` (delete the "Guide names differ from node names" bullet),
`docs/guides/*.j2` cross-links, and the homesite blog posts that link into the guides
(`homesite/src/www/docs/blog/posts/*.md`), then re-run `tools/render_docs.sh` into
homesite. Optionally add `mkdocs-redirects` entries in homesite for the old URLs since
they're public.

## Comments
