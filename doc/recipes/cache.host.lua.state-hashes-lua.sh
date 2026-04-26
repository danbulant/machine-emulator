#!/bin/bash
reads=("$CACHE_DIR/host.lua.config-dump-nothing.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cd "$HERE"
# Dep: ensure config-nothing-to-do.lua exists.
cat "$CACHE_DIR/host.lua.config-dump-nothing.out" > /dev/null
lua run-config-with-hashes.lua config-nothing-to-do 2>&1 | bash "$HERE/strip-ansi.sh" > "$out"
