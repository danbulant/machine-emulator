#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cartesi-machine --max-mcycle=0 --store-config 2>&1 \
    | bash "$HERE/strip-ansi.sh" > "$out"
# Side effect: config-nothing-to-do.lua used by find-htif-putchar.lua and lua state scripts.
sed 's/machine_config = {/return {/' "$out" \
    | grep -v '^Cycles: 0$' \
    > "$HERE/config-nothing-to-do.lua"
