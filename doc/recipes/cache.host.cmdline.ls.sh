#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cartesi-machine -- ls /bin 2>&1 | bash "$HERE/strip-ansi.sh" > "$out"
