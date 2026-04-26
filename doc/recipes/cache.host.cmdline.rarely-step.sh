#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cycles=$(cat "$CACHE_DIR/host.cmdline.cycles-limit-exec.out")
cartesi-machine --max-mcycle="$cycles" --step 2>&1 >/dev/null | bash "$HERE/strip-ansi.sh" > "$out"
