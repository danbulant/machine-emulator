#!/bin/bash
reads=(
    "$CACHE_DIR/host.cmdline.state-hashes-cycles-no-limit.out"
    "$CACHE_DIR/host.cmdline.state-hashes-no-limit.out"
)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cycles=$(cat "$CACHE_DIR/host.cmdline.state-hashes-cycles-no-limit.out")
cat "$CACHE_DIR/host.cmdline.state-hashes-no-limit.out" \
    | bash "$HERE/find-hash.sh" "$cycles" \
    | bash "$HERE/trunc8.sh" > "$out"
