#!/bin/bash
reads=("$CACHE_DIR/host.lua.config-dump-nothing.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
lua run-config-with-hashes.lua config-nothing-to-do > "$out" 2>&1
