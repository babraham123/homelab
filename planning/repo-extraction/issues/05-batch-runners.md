# 05. Move the Calliope and video batch runners into their app repos

Status: resolved
Type: task
Repo: TTS-Narrated-Ebook-Creator (fork), yt-to-audiobook, homelab
Source: maintainer request 2026-10-25

## Change

- `calliope_batch.py` into the TTS-Narrated-Ebook-Creator fork and `yt_to_audiobook_batch.py`
  into yt-to-audiobook, each baked into its image and documented in its README, with hardcoded
  paths made configurable.
- Homelab: stop mounting the scripts; the quadlets run the copies in the images.

## Answer

Done 2026-10-25 (branches `batch-entrypoint`: TTS-Narrated-Ebook-Creator `17fc5b9`,
yt-to-audiobook `21e9749`; homelab branch `move-batch-scripts`).

- Each script is `batch/<name>_batch.py`, copied to `/opt/` by the Containerfile; the image's own
  entrypoint is unchanged. Paths: Calliope `NARRATE_DIR`, `READALOUDS_DIR`, `VOICES_DIR`; video
  `VIDEOS_DIR`, `READALOUDS_DIR`, defaulting to the old mount points. The inbox file contract is
  unchanged. Each README has a "Batch runner" section. yt-to-audiobook's `ruff check` and
  `ruff format --check` pass.
- Homelab: the scripts, their `install -D` lines and the script `Volume=` mounts are gone;
  `Entrypoint=python3` and `Exec=/opt/<name>_batch.py` stay. The `build.sh` comments name the
  script as a build input.
- A runner edit now ships through the image rebuild. The websvcs leftovers are in 09.
