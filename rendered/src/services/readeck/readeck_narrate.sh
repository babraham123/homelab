#!/bin/bash
# Queues Readeck articles labelled `listen` for narration: each one's EPUB export goes
# to Calliope's inbox for the `articles` collection, and the label becomes `narrated`.
# An article whose queueing fails keeps `listen`, and the next run retries it.
# Run by readeck_narrate.timer.
# Usage:
#   src/services/readeck/readeck_narrate.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
# shellcheck source=src/services/readeck/handoff_lib.sh
source "${rendered}/services/readeck/handoff_lib.sh"

readeck=http://read.janedoe.com:8000
resolve=(--resolve "read.janedoe.com:8000:10.11.0.18")
books=/srv/media/books
inbox="${books}/narrate/inbox"
rd_auth="Bearer $(secret readeck_api_token)"

mountpoint -q /srv/media || die "/srv/media is not mounted"

# All pages first: relabelling while paging would shift the offsets.
articles=()
limit=50
offset=0
while :; do
  page=$(api GET "${readeck}/api/bookmarks?labels=listen&limit=${limit}&offset=${offset}" \
    "$rd_auth" "${resolve[@]}")
  mapfile -t -O "${#articles[@]}" articles < <(jq -c '.[]' <<< "$page")
  (( $(jq length <<< "$page") == limit )) || break
  offset=$((offset + limit))
done

failed=0
for article in "${articles[@]}"; do
  id=$(jq -r .id <<< "$article")
  title=$(jq -r '.title // ""' <<< "$article")
  # Filesystem-safe, and the id keeps two articles with one title apart.
  base=$(tr -cs 'A-Za-z0-9' '-' <<< "$title" | cut -c1-60 | sed 's/^-*//; s/-*$//')
  slug="${base:-article}-${id}"
  lang=$(jq -r '((.lang // "") | ascii_downcase | split("-")[0] // "")
    | if test("^[a-z]{2,3}$") then . else "en" end' <<< "$article")

  # Already queued, narrated or failed by an earlier run whose relabel failed.
  if [[ -e "${inbox}/${slug}.epub" || -e "${books}/readalouds/articles/${slug}" ||
        -e "${books}/narrate/failed/${slug}" || -e "${books}/narrate/failed/${slug}.epub" ]]; then
    log "${slug} is already queued or done; relabelling only"
  else
    # Hidden temp names don't match calliope.path's *.epub, so it never sees a partial file.
    if ! api GET "${readeck}/api/bookmarks/${id}/article.epub" "$rd_auth" "${resolve[@]}" \
        -o "${inbox}/.${slug}.epub.tmp"; then
      rm -f "${inbox}/.${slug}.epub.tmp"
      warn "exporting ${id} (${title}) failed; left labelled listen"
      failed=$((failed + 1))
      continue
    fi
    jq -n --arg lang "$lang" '{lang: $lang, collection: "articles"}' > "${inbox}/.${slug}.json.tmp"
    mv "${inbox}/.${slug}.json.tmp" "${inbox}/${slug}.json"
    mv "${inbox}/.${slug}.epub.tmp" "${inbox}/${slug}.epub"
  fi

  if ! api PATCH "${readeck}/api/bookmarks/${id}" "$rd_auth" "${resolve[@]}" \
      -H 'Content-Type: application/json' \
      -d '{"remove_labels": ["listen"], "add_labels": ["narrated"]}' > /dev/null; then
    warn "${slug} is queued, but relabelling ${id} failed; the next run retries it"
    failed=$((failed + 1))
    continue
  fi
  log "queued ${slug} for narration"
done

(( failed == 0 )) || die "${failed} of ${#articles[@]} articles failed"
