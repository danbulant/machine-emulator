#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
# docs:begin
cartesi-machine \
    --append-rom-bootargs="loglevel=8" \
    > "$out" 2>&1
# docs:end
