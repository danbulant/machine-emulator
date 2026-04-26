#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
trap 'rm -f foo.tar foo.ext2' EXIT
tar --sort=name --mtime="2022-01-01" --owner=1000 --group=1000 --numeric-owner \
    -cf foo.tar --directory=foo .
genext2fs -f -b 1024 -a foo.tar foo.ext2
cartesi-machine \
    --flash-drive="label:foo,filename:foo.ext2" \
    -- "cat /mnt/foo/bar.txt" \
    > "$out" 2>&1
