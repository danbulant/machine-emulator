#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.proofs-output-json.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cat "$CACHE_DIR/host.cmdline.proofs-output-json.out" \
    | bash "$HERE/find-hash.sh" root_hash \
    | bash "$HERE/trunc8.sh" > "$out"
