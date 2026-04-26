#!/bin/bash
reads=(
    "$CACHE_DIR/host.cmdline.cycles-limit-exec.out"
    "$CACHE_DIR/host.cmdline.state-hashes-limit-exec.out"
)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
cat "$CACHE_DIR/host.cmdline.state-hashes-limit-exec.out" \
    | bash "$HERE/find-hash.sh" "$cycles" \
    | bash "$HERE/trunc8.sh" > "$out"
