#!/bin/bash
reads=(
    "$CACHE_DIR/host.cmdline.cycles-limit-exec.out"
    "$CACHE_DIR/host.lua.config-dump-nothing.out"
)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cd "$HERE"
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
# Dep: ensure config-nothing-to-do.lua exists.
cat "$CACHE_DIR/host.lua.config-dump-nothing.out" > /dev/null
lua dump-step.lua config-nothing-to-do "$cycles" 2>&1 | bash "$HERE/strip-ansi.sh" > "$out"
