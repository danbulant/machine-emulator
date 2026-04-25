#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key="${0##*/}"; key="${key#cache.}"; key="${key%.sh}"
out="$CACHE_DIR/$key.out"
{
    cartesi-machine -i -- sh 2>&1 <<'MACHINE'
cd /bin
ls
cd /usr/bin
ls
exit
MACHINE
} | bash "$HERE/strip-ansi.sh" > "$out"
