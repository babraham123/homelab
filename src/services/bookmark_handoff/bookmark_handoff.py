#!/usr/bin/env python3
# Moves bookmarks between the reading apps on websvcs; bookmark_handoff.timer runs it
# every 15 minutes in the bookmark_handoff container:
# - linkding bookmarks tagged `toread` go to Readeck, and the tag becomes `readeck`
# - Readeck articles labelled `listen` go to Calliope's inbox as EPUBs for the `articles`
#   collection, and the label becomes `narrated`
# An item whose handoff fails keeps its tag or label, and the next run retries it. The
# apps are reached on their container IPs, not through Traefik, so Authelia isn't in
# the path; each app's own API token is.
# Usage:
#   systemctl start bookmark_handoff

import json
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

import langcodes

books = Path("/books")
inbox = books / "narrate/inbox"
# linkding ids Readeck has accepted. Readeck's API can't look a bookmark up by URL, so
# this is what stops a retry after a failed retag from saving it twice.
sent = Path("/state/sent")
# Chatterbox Multilingual's languages, the TTS behind Calliope; anything else is read
# as English. Ref: https://github.com/resemble-ai/chatterbox
narrated_langs = {"ar", "da", "de", "el", "en", "es", "fi", "fr", "he", "hi", "it", "ja",
                  "ko", "ms", "nl", "no", "pl", "pt", "ru", "sv", "sw", "tr", "zh"}


def log(message):
  print(message, flush=True)


def warn(message):
  print(f"warning: {message}", file=sys.stderr, flush=True)


class App:
  """One app's REST API, on its container IP under its public host name."""

  # Usage: App(NAME, SCHEME); NAME_URL, NAME_HOST and NAME_API_TOKEN from the environment
  def __init__(self, name, scheme):
    self.url = os.environ[f"{name}_URL"]
    self.host = os.environ[f"{name}_HOST"]
    self.auth = f"{scheme} {os.environ[f'{name}_API_TOKEN'].strip()}"

  # Raises on a non-2xx status. PATH may be a full URL the app built, like linkding's
  # `next`; only its path and query are used, since its host isn't the container IP.
  def request(self, method, path, body=None, raw=False):
    parts = urllib.parse.urlsplit(path)
    path = parts.path + (f"?{parts.query}" if parts.query else "")
    request = urllib.request.Request(
        self.url + path, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Host": self.host, "Authorization": self.auth,
                 **({} if body is None else {"Content-Type": "application/json"})})
    with urllib.request.urlopen(request, timeout=60) as response:
      data = response.read()
    return data if raw else json.loads(data or "null")


def slug(article):
  """Filesystem-safe, and the id keeps two articles with one title apart."""
  base = re.sub(r"[^A-Za-z0-9]+", "-", article.get("title") or "")[:60].strip("-")
  return f"{base or 'article'}-{article['id']}"


def narration_lang(tag):
  """The article's language as Calliope's --lang: en_US, eng and EN all become en."""
  try:
    lang = langcodes.Language.get(tag or "").language
  except ValueError:
    return "en"
  # Bokmål and Nynorsk are both Norwegian to the TTS.
  lang = {"nb": "no", "nn": "no"}.get(lang, lang)
  return lang if lang in narrated_langs else "en"


def linkding_to_readeck(linkding, readeck):
  """Returns how many bookmarks failed, of how many."""
  # All pages first: retagging while paging would shift the offsets.
  bookmarks, url = [], "/api/bookmarks/?q=%23toread&limit=100"
  while url:
    page = linkding.request("GET", url)
    bookmarks += page["results"]
    url = page.get("next")

  sent.touch()
  done = set(sent.read_text().split())
  failed = 0
  for bookmark in bookmarks:
    ld_id, link = str(bookmark["id"]), bookmark["url"]
    tags = [t for t in bookmark["tag_names"] if t != "toread"]
    if ld_id in done:
      log(f"{link} (linkding {ld_id}) is already in Readeck; retagging only")
    else:
      body = {"url": link, "labels": tags}
      if bookmark.get("title"):
        body["title"] = bookmark["title"]
      try:
        readeck.request("POST", "/api/bookmarks", body)
      except OSError as e:
        warn(f"Readeck refused {link} (linkding {ld_id}): {e}; left tagged toread")
        failed += 1
        continue
      with sent.open("a") as f:
        f.write(f"{ld_id}\n")
    try:
      linkding.request("PATCH", f"/api/bookmarks/{ld_id}/", {"tag_names": tags + ["readeck"]})
    except OSError as e:
      warn(f"{link} is in Readeck, but retagging linkding {ld_id} failed: {e}; the next run retries it")
      failed += 1
      continue
    log(f"handed off {link} (linkding {ld_id})")
  return failed, len(bookmarks)


def readeck_to_narrate(readeck):
  """Returns how many articles failed, of how many."""
  if not inbox.is_dir():
    log(f"no {inbox} until calliope is installed; listen labels wait")
    return 0, 0
  # All pages first: relabelling while paging would shift the offsets.
  articles, limit = [], 50
  while True:
    page = readeck.request("GET", f"/api/bookmarks?labels=listen&limit={limit}&offset={len(articles)}")
    articles += page
    if len(page) < limit:
      break

  failed = 0
  for article in articles:
    name, rd_id = slug(article), article["id"]
    # Already queued, narrated or failed by an earlier run whose relabel failed.
    done = [inbox / f"{name}.epub", books / "readalouds/articles" / name,
            books / "narrate/failed" / name, books / "narrate/failed" / f"{name}.epub"]
    if any(p.exists() for p in done):
      log(f"{name} is already queued or done; relabelling only")
    else:
      # Hidden temp names don't match calliope.path's *.epub, so it never sees a partial file.
      epub, spec = inbox / f".{name}.epub.tmp", inbox / f".{name}.json.tmp"
      try:
        epub.write_bytes(readeck.request("GET", f"/api/bookmarks/{rd_id}/article.epub", raw=True))
      except OSError as e:
        epub.unlink(missing_ok=True)
        warn(f"exporting {rd_id} ({article.get('title')}) failed: {e}; left labelled listen")
        failed += 1
        continue
      spec.write_text(json.dumps({"lang": narration_lang(article.get("lang")), "collection": "articles"}))
      spec.rename(inbox / f"{name}.json")
      epub.rename(inbox / f"{name}.epub")
    try:
      readeck.request("PATCH", f"/api/bookmarks/{rd_id}",
                      {"remove_labels": ["listen"], "add_labels": ["narrated"]})
    except OSError as e:
      warn(f"{name} is queued, but relabelling {rd_id} failed: {e}; the next run retries it")
      failed += 1
      continue
    log(f"queued {name} for narration")
  return failed, len(articles)


def main():
  linkding, readeck = App("LINKDING", "Token"), App("READECK", "Bearer")
  errors = []
  # Each job runs whatever the other did: one app being down shouldn't hold up the other.
  for job, run in [("linkding to Readeck", lambda: linkding_to_readeck(linkding, readeck)),
                   ("Readeck to narration", lambda: readeck_to_narrate(readeck))]:
    try:
      failed, total = run()
    except OSError as e:
      errors.append(f"{job}: {e}")
      continue
    if failed:
      errors.append(f"{job}: {failed} of {total} failed")
  for error in errors:
    print(f"error: {error}", file=sys.stderr)
  sys.exit(1 if errors else 0)


if __name__ == "__main__":
  main()
