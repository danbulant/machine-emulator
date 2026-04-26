#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
# docs:begin
cartesi-machine \
    --initial-hash \
    --final-hash \
    > "$out" 2>&1
# docs:end
