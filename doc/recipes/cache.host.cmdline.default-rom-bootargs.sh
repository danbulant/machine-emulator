#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
cartesi-machine --store-config 2>&1 \
    | grep bootargs \
    | sed 's/.* = //' \
    | sed 's/,$//' \
    > "$out"
