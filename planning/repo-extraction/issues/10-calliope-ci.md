# 10. CI for TTS-Narrated-Ebook-Creator

Status: resolved
Type: task
Repo: TTS-Narrated-Ebook-Creator (fork)
Source: maintainer request 2026-10-25

## Problem

The fork now carries the batch runner the homelab's quadlet runs, but has no CI or Renovate. Its
image (CUDA, PyTorch, Chatterbox) is likely too large to build on GitHub's free runners.

## Options

- Tests and lint only (`pytest` with the fake backend, `ruff check`), no image build.
- An image build on a larger or self-hosted runner.
- Renovate for the Containerfile's base images and `uv.lock`, independent of CI.

## Comments

- 2026-10-25 agent: done in the fork (40be31a, db8c15f), the first option plus Renovate.
  - CI runs `ruff check`, `ruff format --check` and `pytest` with the fake backend on uv's Python
    3.12, with ffmpeg and epubcheck so no test skips. No image build.
  - `ruff.toml`: 100 columns, rules `E9` and `F`; the upstream `src/epub_processor_*.py` scripts
    are excluded so merges from upstream stay clean.
  - Renovate holds `nvidia/cuda` to 12.4.x and skips torch, torchaudio and CTranslate2, whose newer
    builds drop CUDA 12.4 or Pascal; pyproject ranges stay as written and only `uv.lock` moves.
