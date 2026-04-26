#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cartesi-machine \
    --rom-image="/opt/cartesi/share/images/rom.bin" \
    --ram-length=64Mi \
    --ram-image="/opt/cartesi/share/images/linux.bin" \
    --flash-drive="label:root,filename:/opt/cartesi/share/images/rootfs.ext2" \
    --max-mcycle=0 \
    --store-config \
    -- "ls /bin" \
    2>&1 | bash "$HERE/strip-ansi.sh" > "$out"
