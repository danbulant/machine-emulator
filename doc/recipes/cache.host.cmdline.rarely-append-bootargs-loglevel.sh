#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
cartesi-machine --append-rom-bootargs="loglevel=8" 2>&1 | bash "$HERE/strip-ansi.sh" > "$out"
