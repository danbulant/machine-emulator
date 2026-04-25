#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
# Dep: ensure config-nothing-to-do.lua exists.
cat "$CACHE_DIR/host.lua.config-dump-nothing.out" > /dev/null
(cd "$HERE" && lua dump-step.lua config-nothing-to-do "$cycles") 2>&1 \
    | bash "$HERE/strip-ansi.sh" > "$out"
