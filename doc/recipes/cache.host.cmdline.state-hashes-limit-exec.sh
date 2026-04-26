#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
cartesi-machine --max-mcycle="$cycles" --initial-hash --final-hash \
    > "$out" 2>&1
