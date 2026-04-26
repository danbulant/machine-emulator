#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
# docs:begin
cartesi-machine --max-mcycle=$cycles > "$out" 2>&1
# docs:end
