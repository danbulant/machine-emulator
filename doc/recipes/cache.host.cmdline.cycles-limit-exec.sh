#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
# Dep: ensure config-nothing-to-do.lua exists (side effect of host.lua.config-dump-nothing).
cat "$CACHE_DIR/host.lua.config-dump-nothing.out" > /dev/null
(cd "$HERE" && lua find-htif-putchar.lua) 2>&1 >/dev/null | bash "$HERE/strip-ansi.sh" > "$out"
