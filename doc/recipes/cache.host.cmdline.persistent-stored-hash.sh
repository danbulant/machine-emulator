#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
trap 'rm -rf machine-store' EXIT
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
cartesi-machine --max-mcycle="$cycles" --store="machine-store" > /dev/null 2>&1
cartesi-machine-stored-hash machine-store > "$out" 2>&1
