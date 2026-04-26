#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.state-hashes-limit-exec.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cat "$CACHE_DIR/host.cmdline.state-hashes-limit-exec.out" \
    | bash "$HERE/find-hash.sh" 0 \
    | bash "$HERE/trunc8.sh" > "$out"
