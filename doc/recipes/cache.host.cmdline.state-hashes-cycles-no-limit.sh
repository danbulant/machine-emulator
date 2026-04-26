#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.state-hashes-no-limit.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cat "$CACHE_DIR/host.cmdline.state-hashes-no-limit.out" | bash "$HERE/last-cycles.sh" > "$out"
