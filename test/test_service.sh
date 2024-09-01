#!/usr/bin/env bash
# Tests how podman passes env vars and secrets to a container.

set -euo pipefail

echo "starting"
echo "hash: $HS_UI_HASH"
echo "BB: $BB"
echo "AA: $AA"
echo "ending"
