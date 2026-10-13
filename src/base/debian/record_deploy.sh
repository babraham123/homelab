#!/bin/bash
# Publishes the commit the uploaded tree was rendered from (/root/homelab-rendered/DEPLOYED,
# written by tools/render_src.sh) as node_exporter textfile metrics, for the "Deployed
# commits" table on the Homelab alerts dashboard. Nothing alerts on them.
# Run by tools/upload_src.sh right after it moves the tree into place.
# Usage:
#   sudo /root/homelab-rendered/src/base/debian/record_deploy.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"
require_root

deployed=/root/homelab-rendered/DEPLOYED
textfile=/var/lib/node_exporter/textfile_collector
metrics="${textfile}/homelab_deploy.prom"

# No node_exporter, nothing to publish to
[[ -d $textfile ]] || exit 0
# A render outside a git checkout records no commit; an old row would claim the wrong one
if [[ ! -f $deployed ]]; then
  rm -f "$metrics"
  exit 0
fi

value() { sed -n "s/^$1=//p" "$deployed"; }
sha=$(value sha)
dirty=$(value dirty)
rendered_at=$(value rendered_at)
[[ $sha =~ ^[0-9a-f]{40}$ && $dirty =~ ^[0-9]+$ && $rendered_at =~ ^[0-9]+$ ]] ||
  die "${deployed} needs sha=<40 hex>, dirty=<count> and rendered_at=<epoch> lines"

{
  echo '# HELP homelab_deployed_info Commit the rendered tree came from; dirty = uncommitted files'
  echo '# TYPE homelab_deployed_info gauge'
  echo "homelab_deployed_info{sha=\"${sha}\",dirty=\"${dirty}\"} 1"
  echo '# HELP homelab_deployed_timestamp_seconds When the deployed tree was rendered'
  echo '# TYPE homelab_deployed_timestamp_seconds gauge'
  echo "homelab_deployed_timestamp_seconds ${rendered_at}"
} > "${metrics}.tmp"
chmod 644 "${metrics}.tmp"
# node_exporter never reads a half-written file
mv "${metrics}.tmp" "$metrics"
