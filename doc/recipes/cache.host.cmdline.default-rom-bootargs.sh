#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cartesi-machine --store-config 2>&1 \
    | grep bootargs \
    | sed 's/.* = //' \
    | sed 's/,$//' \
    > "$out"
