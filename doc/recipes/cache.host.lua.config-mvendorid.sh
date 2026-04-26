#!/bin/bash
reads=("$CACHE_DIR/host.lua.config-dump-nothing.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cat "$CACHE_DIR/host.lua.config-dump-nothing.out" | bash "$HERE/find-lua-val.sh" mvendorid > "$out"
