#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
cat "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-client.out"     | bash "$HERE/all-hashes.sh"     | sed -n '2p'     | bash "$HERE/trunc8.sh" > "$out"
