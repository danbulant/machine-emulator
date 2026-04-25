#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
cat "$CACHE_DIR/host.cmdline.proofs-output-json.out" \
    | bash "$HERE/find-hash.sh" root_hash \
    | bash "$HERE/trunc8.sh" > "$out"
