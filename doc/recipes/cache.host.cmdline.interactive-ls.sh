#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
{
    cartesi-machine -i -- sh 2>&1 <<'MACHINE'
ls /bin
exit
MACHINE
} | bash "$HERE/strip-ansi.sh" > "$out"
