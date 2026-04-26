#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cartesi-machine \
    --flash-drive=label:hello,filename:hello.ext2 \
    -- /mnt/hello/hello-cpp \
    > "$out" 2>&1
