# 03. Research: Storyteller's own alignment for a captionless video

Status: ready-for-human
Type: research
Repo: homelab
Source: maintainer request 2026-10-23
Blocked by: 02

## Question

Storyteller aligns an audiobook to an ebook itself: upload the audio and a plain EPUB of
the transcript and it produces the read-along. The narrated-ebooks spec rejected it as hours
per book on this hardware, but a one-hour video is a fraction of a book, and it would make
04 unnecessary. Is it fast enough, and good enough, for the captionless case?

## Method

1. Pick one captionless talk of about an hour, or strip the captions from one that has them
   so the result can be compared with 02's output.
2. Transcribe it once with any tool (even Parakeet by hand on the laptop) into a plain EPUB
   with one paragraph per sentence.
3. Upload the EPUB and the m4a to Storyteller as a new book and start processing. Record
   wall time, CPU and VRAM on websvcs, and whether whisper and Calliope stayed usable.
4. Spot-check the highlight at the start, middle and end against 02's cue-built EPUB.

## Answer

(Decision: if Storyteller's alignment finishes in well under the hour the video runs for,
and the highlight is no worse than the cue-built one, 04 becomes "upload audio plus
transcript to Storyteller" and the EPUB builder is only used when captions exist. Otherwise
04 as specified.)
