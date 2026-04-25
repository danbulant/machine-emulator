#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
cycles=$(cat "$CACHE_DIR/host.cmdline.proofs-output-run.out" | bash "$HERE/last-cycles.sh")
printf '%d\n' "$((cycles - 10))" > "$out"
