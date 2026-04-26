#!/bin/bash
reads=(
    "$CACHE_DIR/host.cmdline.cycles-limit-exec.out"
    "$CACHE_DIR/host.cmdline.state-hashes-final-limit-exec.out"
)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
hash=$(cat "$CACHE_DIR/host.cmdline.state-hashes-final-limit-exec.out")
trap 'rm -rf "machine-$hash"' EXIT
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
cartesi-machine --max-mcycle=$cycles --store="machine-$hash" > /dev/null 2>&1
# docs:begin
cartesi-machine-stored-hash machine-$hash > "$out" 2>&1
# docs:end
