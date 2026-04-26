#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
# docs:begin
cartesi-machine \
    --append-rom-bootargs="single=yes" \
    -- id \
    > "$out" 2>&1
# docs:end
