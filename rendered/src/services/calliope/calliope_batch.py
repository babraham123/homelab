#!/usr/bin/env python3
# Narrates the oldest EPUB in the inbox into a read-along EPUB, one book per run.
# The calliope quadlet runs this as its entrypoint; calliope.path and calliope.timer
# start it again until the inbox is empty.
# Inbox: Title.epub, optionally Title.json with {"lang", "voice", "collection"}.
# A book stopped part way (SIGTERM, pve2 going down) stays in the inbox, and its
# sentence cache in work/ lets the next run resume it.
# Usage (inside the container):
#   calliope_batch.py

import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

narrate = Path("/narrate")
inbox = narrate / "inbox"
work = narrate / "work"
failed = narrate / "failed"
readalouds = Path("/readalouds")
voices = Path("/voices")
safe_name = re.compile(r"^[A-Za-z0-9_-]+$")

child = None


def log(msg):
  print(msg, flush=True)


def notify(title, msg, priority):
  token = os.environ.get("NTFY_ALERT_ACCESS_TOKEN")
  url = os.environ.get("NTFY_URL")
  if not token or not url:
    return
  req = urllib.request.Request(url, data=msg.encode(), headers={
      "Authorization": f"Bearer {token}",
      "X-Title": title,
      "X-Priority": str(priority),
      "X-Tags": "books",
  })
  try:
    urllib.request.urlopen(req, timeout=30).close()
  except Exception as e:
    log(f"warning: ntfy post failed: {e}")


def stop(signum, frame):
  # Leave the book in the inbox: the next run resumes it from the cache.
  if child and child.poll() is None:
    child.terminate()
    try:
      child.wait(timeout=60)
    except subprocess.TimeoutExpired:
      child.kill()
  log("stopped; the book stays in the inbox and resumes on the next run")
  sys.exit(128 + signum)


def options(book):
  spec = book.with_suffix(".json")
  opts = json.loads(spec.read_text()) if spec.exists() else {}
  opts.setdefault("lang", "en")
  opts.setdefault("voice", "default")
  opts.setdefault("collection", "books")
  for key in ("voice", "collection"):
    if not safe_name.match(opts[key]):
      raise ValueError(f"{key} must match {safe_name.pattern}: {opts[key]!r}")
  if not re.match(r"^[a-z]{2,3}$", opts["lang"]):
    raise ValueError(f"lang must be an ISO 639 code: {opts['lang']!r}")
  if not (voices / f"{opts['voice']}.wav").exists():
    raise ValueError(f"no voice {opts['voice']}.wav in /etc/opt/calliope/voices")
  return opts


def move_inputs(book, dest):
  dest.mkdir(parents=True, exist_ok=True)
  for f in (book, book.with_suffix(".json")):
    if f.exists():
      shutil.move(str(f), dest / f.name)


def main():
  signal.signal(signal.SIGTERM, stop)
  signal.signal(signal.SIGINT, stop)
  for d in (inbox, work, failed):
    d.mkdir(parents=True, exist_ok=True)

  books = sorted(inbox.glob("*.epub"), key=lambda p: p.stat().st_mtime)
  if not books:
    log("inbox is empty")
    return 0
  book = books[0]
  title = book.stem
  staging = work / title / "out"
  log(f"narrating {book.name}")

  try:
    opts = options(book)
  except (ValueError, json.JSONDecodeError) as e:
    log(f"error: {book.name}: {e}")
    move_inputs(book, failed)
    notify("Narration failed", f"{title}: {e}", 4)
    return 1

  voice = voices / f"{opts['voice']}.wav"
  if staging.exists():
    shutil.rmtree(staging)
  staging.mkdir(parents=True)
  global child
  started = time.monotonic()
  child = subprocess.Popen([
      "calliope", str(book), str(staging / f"{title}.readaloud.epub"),
      "--voice", str(voice), "--lang", opts["lang"],
      "--work-dir", str(work / title / "cache"),
  ])
  rc = child.wait()
  hours = (time.monotonic() - started) / 3600

  if rc != 0:
    log(f"error: calliope exited {rc} on {book.name} after {hours:.1f} h")
    dest = failed / title
    move_inputs(book, dest)
    for f in staging.iterdir():
      shutil.move(str(f), dest / f.name)
    notify("Narration failed", f"{title}: calliope exited {rc}; see {dest}", 4)
    return 1

  dest = readalouds / opts["collection"] / title
  dest.mkdir(parents=True, exist_ok=True)
  # Storyteller writes metadata edits back into the books, as its own user.
  uid, gid = (int(n) for n in os.environ.get("READALOUDS_OWNER", "0:0").split(":"))
  for d in (dest.parent, dest):
    os.chown(d, uid, gid)
  # The report first and the EPUB last, so an import never sees a book without one.
  for f in sorted(staging.iterdir(), key=lambda p: p.suffix == ".epub"):
    tmp = dest / f".{f.name}.tmp"
    shutil.copyfile(f, tmp)
    os.chown(tmp, uid, gid)
    os.replace(tmp, dest / f.name)
  book.unlink()
  book.with_suffix(".json").unlink(missing_ok=True)
  shutil.rmtree(work / title)
  log(f"done: {dest} after {hours:.1f} h")
  notify("Narration done", f"{title} is in {opts['collection']} ({hours:.1f} h)", 3)
  return 0


if __name__ == "__main__":
  sys.exit(main())
