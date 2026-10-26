# 04. Extract bookmark_handoff to bookmark-handoff

Status: resolved
Type: task
Repo: bookmark-handoff (new), homelab
Source: maintainer request 2026-10-25

## Change

- New repo babraham123/bookmark-handoff: `bookmark_handoff.py`, its Containerfile and hashed
  requirements, with app URLs, tokens, tag names and paths from the environment. README, tests
  that need no live services.
- Homelab: `build.sh` builds from the new repo; the quadlet, timer and secrets stay.

## Answer

Done 2026-10-25 (bookmark-handoff `1b02675`; homelab branch `extract-bookmark-handoff`).

- **Repo:** `LINKDING_URL`, `LINKDING_API_TOKEN`, `LINKDING_HOST` and the same for `READECK_*`
  (the names the quadlet already passed); tags `TOREAD_TAG`, `READECK_TAG`, `LISTEN_LABEL`,
  `NARRATED_LABEL`, `TOLISTEN_TAG`, `TRANSCRIBED_TAG`; paths `BOOKS_DIR`, `NARRATE_DIR`,
  `VIDEOS_DIR`, `READALOUDS_DIR`, `STATE_DIR` and the two collections. Defaults are the homelab's
  values. `*_HOST` is optional; a job whose app has no URL is skipped, and a URL without its token
  exits 1. Query strings go through `urlencode`; the default requests are byte-identical. The
  inbox files are unchanged. 24 unittest cases against faked linkding and Readeck APIs.
- **Base image:** a literal `FROM docker.io/library/python:3.14-alpine`, since
  `github_base_images` can't resolve a `FROM ${ARG}`.
- **Homelab:** `src/services/bookmark_handoff/build.sh` is `github_build` from the new repo; the
  script, Containerfile and requirements are gone. The quadlet's `Environment=` and `Secret=` lines
  are unchanged.
