# YouTube videos as read-along EPUBs

Turn a YouTube video into a read-along EPUB in Storyteller: the audio track plus its
transcript, highlighted as it plays. A video is tagged in linkding and, within the hour,
it is in Storyteller's **Videos** collection. The job reuses the narrated-ebooks pipeline
([spec](../narrated-ebooks/spec.md)) with the TTS step replaced: yt-dlp supplies the audio
and the caption cues, and the SMIL is written from the cue timestamps instead of clip
lengths, so no alignment and no GPU.

Maintainer decisions (2026-10-23):

- No podcast server. Audiobookshelf, Jellyfin and a static RSS feed were compared and
  rejected: the use is one-off "listen to this talk later", which is how the reading
  pipeline is already used, and Storyteller's apps and OPDS clients are the players.
  Storyteller has no audio-only mode, so every video carries its transcript.
- Input is a linkding tag, `tolisten`, handed off by `bookmark_handoff` like `toread`
  and `listen`. The tag becomes `transcribed` once queued.
- Audio only, YouTube's AAC track as is (`ba[ext=m4a]`), no transcode, with the
  metadata and thumbnail embedded.
- Captions come from YouTube: uploaded subtitles first, auto-captions otherwise. They are
  rough, but they carry timestamps, which is what the highlight needs.
- Sponsor segments are cut with SponsorBlock, in `mark` mode: yt-dlp writes the segments
  to `info.json` and the builder cuts the audio and shifts the cues together, since
  yt-dlp's own `remove` mode does not shift subtitles. Categories: `sponsor`,
  `selfpromo`, `interaction`, `intro`, `outro`, `preview`. `filler` stays on.
- Videos without captions are transcribed on the CPU by Parakeet TDT 0.6B v3
  (sherpa-onnx or parakeet.cpp), not whisper: better English accuracy and speed, native
  word timestamps and punctuation, and no CUDA pin on the P4. Its 25 languages are
  European; a captionless video in another language fails with a notification rather
  than carrying a second engine. Before any of that is written, 03 trials Storyteller's
  own alignment on one video, since a one-hour video is a fraction of the book that made
  it too slow for narrated-ebooks.
- A separate container, `yt_to_audiobook`, not a job inside `bookmark_handoff`: yt-dlp plus
  ffmpeg is a larger image that churns monthly, a download can outlast the handoff's
  600 s timeout, and only this container needs egress to YouTube and SponsorBlock.
- Output lands in `/srv/media/books/readalouds/videos/<Title>/`, a third Storyteller
  collection beside `books` and `articles`.

Constraints:

- websvcs is on pve2, which is on demand: the timer is `Persistent=true`, and a video
  tagged while pve2 is off is fetched at the next boot. The library is unreachable while
  pve2 is off; the Storyteller app's offline downloads cover listening away from home.
- `/srv/media` is mergerfs. Nothing in this pipeline relies on inotify over it; the path
  unit polls `PathExistsGlob`, as `calliope.path` does.
- yt-dlp breaks roughly monthly when YouTube changes. It is pinned by hash in
  `requirements.txt`; the fix is a bump and a deploy. A residential IP should not need
  cookies; if YouTube starts demanding sign-in, a cookies file becomes a SOPS secret
  mounted read-only.
- The media array is parity-only. Downloads are re-fetchable and are not backed up.
  Storyteller's position data is in its own database, already covered.

## Flow

```mermaid
flowchart LR
    linkding["linkding<br/>tag tolisten"] -- "bookmark_handoff<br/>(every 15 min)" --> inbox["videos/inbox/<slug>.json"]
    inbox -- "yt_to_audiobook.path" --> fetch["yt_to_audiobook<br/>yt-dlp + SponsorBlock"]
    fetch -- "captions" --> build["EPUB 3 + SMIL<br/>from the VTT cues"]
    fetch -- "no captions" --> stt["Parakeet (CPU)"] --> build
    build --> lib["readalouds/videos/<Title>/"] --> storyteller["Storyteller<br/>Videos collection"]
```

## Issues

| # | Title | Status | Type |
| --- | --- | --- | --- |
| [01](issues/01-linkding-tolisten-handoff.md) | Hand linkding `tolisten` bookmarks to the video inbox | `ready-for-agent` | task |
| [02](issues/02-yt-to-audiobook-fetcher.md) | Fetch the audio and captions and build the read-along EPUB | `ready-for-agent` | task |
| [03](issues/03-storyteller-alignment-trial.md) | Research: Storyteller's own alignment for a captionless video | `ready-for-human` | research |
| [04](issues/04-parakeet-stt-fallback.md) | Transcribe captionless videos with Parakeet on the CPU | `ready-for-agent` | task |
