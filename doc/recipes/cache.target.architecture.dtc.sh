#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cartesi-machine \
    --append-rom-bootargs="single=yes" \
    --rollup \
    -- "dtc -I dtb -O dts /sys/firmware/fdt" 2>&1 \
    > "$out" 2>&1
