#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.proofs-output-run.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cycles=$(cat "$CACHE_DIR/host.cmdline.proofs-output-run.out" | bash "$HERE/last-cycles.sh")
printf '%d\n' "$((cycles - 10))" > "$out"
