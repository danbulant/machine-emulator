#!/bin/bash
reads=("$CACHE_DIR/host.lua.config-dump-nothing.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cd "$HERE"
# Dep: ensure config-nothing-to-do.lua exists (side effect of host.lua.config-dump-nothing).
cat "$CACHE_DIR/host.lua.config-dump-nothing.out" > /dev/null
lua find-htif-putchar.lua 2>&1 >/dev/null | bash "$HERE/strip-ansi.sh" > "$out"
