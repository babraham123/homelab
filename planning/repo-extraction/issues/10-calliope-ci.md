# 10. CI for TTS-Narrated-Ebook-Creator

Status: needs-triage
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
