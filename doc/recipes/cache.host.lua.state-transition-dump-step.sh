#!/bin/bash
reads=(
    "$CACHE_DIR/host.cmdline.cycles-limit-exec.out"
    "$CACHE_DIR/host.lua.config-dump-nothing.out"
)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
lua dump-step.lua config-nothing-to-do "$cycles" > "$out" 2>&1
