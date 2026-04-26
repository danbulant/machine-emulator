#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.templates-hash.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cat "$CACHE_DIR/host.cmdline.templates-hash.out" | bash "$HERE/trunc8.sh" > "$out"
