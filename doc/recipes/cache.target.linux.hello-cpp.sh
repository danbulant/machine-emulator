#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cd "$HERE"
cartesi-machine \
    --flash-drive=label:hello,filename:hello.ext2 \
    -- /mnt/hello/hello-cpp \
    2>&1 | bash "$HERE/strip-ansi.sh" > "$out"
