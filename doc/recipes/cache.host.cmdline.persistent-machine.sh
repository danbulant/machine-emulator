#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
(cd "$HERE" && \
    cartesi-machine --max-mcycle="$cycles" --store="machine-store" > /dev/null 2>&1 && \
    cartesi-machine --load="machine-store" --initial-hash --final-hash 2>&1 | bash "$HERE/strip-ansi.sh" > "$out" && \
    rm -rf machine-store)
