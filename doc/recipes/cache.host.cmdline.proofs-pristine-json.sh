#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
(cd "$HERE" && \
    cartesi-machine \
        --flash-drive="label:input,length:1<<12" \
        --flash-drive="label:output,length:1<<12" \
        --max-mcycle=0 \
        --final-hash \
        --store="calculator-template" \
        -- $'dd status=none if=$(flashdrive input) | lua -e \'print((string.unpack("z", io.read("a"))))\' | bc | dd status=none of=$(flashdrive output)' \
        > /dev/null 2>&1 && \
    cartesi-machine \
        --load="calculator-template" \
        --max-mcycle=0 \
        --initial-hash \
        --initial-proof="address:0x9000000000000000,log2_size:12,filename:pristine-input-proof" \
        > /dev/null 2>&1 && \
    cat pristine-input-proof > "$out" && \
    rm -rf calculator-template pristine-input-proof)
