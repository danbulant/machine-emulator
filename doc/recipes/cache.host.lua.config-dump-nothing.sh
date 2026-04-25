#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
cartesi-machine --max-mcycle=0 --store-config 2>&1 \
    | bash "$HERE/strip-ansi.sh" > "$out"
# Side effect: config-nothing-to-do.lua used by find-htif-putchar.lua and lua state scripts.
sed 's/machine_config = {/return {/' "$out" \
    | grep -v '^Cycles: 0$' \
    > "$HERE/config-nothing-to-do.lua"
