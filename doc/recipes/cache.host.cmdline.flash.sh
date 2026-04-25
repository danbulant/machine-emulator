#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
(cd "$HERE" && {
    tar --sort=name --mtime="2022-01-01" --owner=1000 --group=1000 --numeric-owner \
        -cf foo.tar --directory=foo .
    genext2fs -f -b 1024 -a foo.tar foo.ext2
    rm -f foo.tar
    cartesi-machine \
        --flash-drive="label:foo,filename:foo.ext2" \
        -- "cat /mnt/foo/bar.txt" \
        2>&1 | bash "$HERE/strip-ansi.sh" > "$out"
    rm -f foo.ext2
})
