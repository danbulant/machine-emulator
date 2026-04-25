#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
cat "$CACHE_DIR/host.cmdline.state-hashes-limit-exec.out" \
    | bash "$HERE/find-hash.sh" "$cycles" \
    | bash "$HERE/trunc8.sh" > "$out"
