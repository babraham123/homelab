#!/usr/bin/env python3
# Turns the oldest YouTube request in the inbox into a read-along EPUB, one video per run,
# with yt-to-audiobook (github.com/babraham123/yt-to-audiobook, installed in the image).
# The yt_to_audiobook quadlet runs this as its entrypoint; yt_to_audiobook.path and
# yt_to_audiobook.timer start it again until the inbox is empty.
# Inbox: <slug>.json, {"url", "title", "linkding_id", "lang"}, written by bookmark_handoff.
# A run stopped part way (SIGTERM, pve2 going down) leaves the request in the inbox and
# work/<slug>/ in place, and the next run resumes the download.
# Usage (inside the container):
#   yt_to_audiobook_batch.py

import json
import logging
import os
import shutil
import signal
import sys
import time
import urllib.request
from pathlib import Path

from yt_to_audiobook import Failure, convert, stop_child

videos = Path("/videos")
inbox = videos / "inbox"
work = videos / "work"
failed = videos / "failed"
readalouds = Path("/readalouds/videos")


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
  # Leave the request in the inbox and work/<slug> in place: the next run resumes them.
  stop_child()
  log("stopped; the request stays in the inbox and resumes on the next run")
  sys.exit(128 + signum)


def read_request(path):
  req = json.loads(path.read_text())
  if not isinstance(req, dict) or not isinstance(req.get("url"), str):
    raise Failure("the request needs a url")
  req.setdefault("lang", "en")
  return req


def move_to_failed(request, wdir, slug):
  dest = failed / slug
  dest.mkdir(parents=True, exist_ok=True)
  items = [request] + (sorted(wdir.iterdir()) if wdir.exists() else [])
  for f in items:
    if not f.exists():
      continue
    target = dest / f.name
    if target.is_dir():
      shutil.rmtree(target)
    shutil.move(str(f), target)
  if wdir.exists():
    shutil.rmtree(wdir)
  return dest


def deliver(out, slug):
  dest = readalouds / slug
  dest.mkdir(parents=True, exist_ok=True)
  # Storyteller writes metadata edits back into the books, as its own user.
  uid, gid = (int(n) for n in os.environ.get("READALOUDS_OWNER", "0:0").split(":"))
  for d in (dest.parent, dest):
    os.chown(d, uid, gid)
  # The report first and the EPUB last, so an import never sees a book without one.
  for f in sorted(out.iterdir(), key=lambda p: p.suffix == ".epub"):
    tmp = dest / f".{f.name}.tmp"
    shutil.copyfile(f, tmp)
    os.chown(tmp, uid, gid)
    os.replace(tmp, dest / f.name)
  return dest


def main():
  signal.signal(signal.SIGTERM, stop)
  signal.signal(signal.SIGINT, stop)
  # yt-to-audiobook logs its progress (caption track, cuts) through logging.
  logging.basicConfig(level=logging.INFO, format="%(message)s", stream=sys.stdout)
  for d in (inbox, work, failed):
    d.mkdir(parents=True, exist_ok=True)

  requests = sorted((p for p in inbox.glob("*.json") if not p.name.startswith(".")),
                    key=lambda p: p.stat().st_mtime)
  if not requests:
    log("inbox is empty")
    return 0
  request = requests[0]
  slug = request.stem
  wdir = work / slug
  downloads = wdir / "download"
  out = wdir / "out"
  log(f"fetching {request.name}")
  started = time.monotonic()
  try:
    req = read_request(request)
    if out.exists():
      shutil.rmtree(out)
    out.mkdir(parents=True)
    report = convert(req["url"], out / f"{slug}.readaloud.epub", req["lang"], downloads)
    report["linkding_id"] = req.get("linkding_id")
    (out / f"{slug}.report.json").write_text(json.dumps(report, indent=2) + "\n")
    dest = deliver(out, slug)
  except Exception as e:
    # Out of the inbox whatever went wrong, or the path unit would restart it in a loop.
    reason = str(e) if isinstance(e, Failure) else f"{type(e).__name__}: {e}"
    log(f"error: {request.name}: {reason}")
    dest = move_to_failed(request, wdir, slug)
    notify("Read-along failed", f"{slug}: {reason}; see {dest}", 4)
    return 1

  request.unlink()
  shutil.rmtree(wdir)
  minutes_taken = (time.monotonic() - started) / 60
  log(f"done: {dest} after {minutes_taken:.0f} min")
  notify("Read-along done", f"{slug} is in videos ({minutes_taken:.0f} min)", 3)
  return 0


if __name__ == "__main__":
  sys.exit(main())
