#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
{
    cartesi-machine -i -- sh 2>&1 <<'MACHINE'
cd /bin
ls
cd /usr/bin
ls
exit
MACHINE
} > "$out" 2>&1
