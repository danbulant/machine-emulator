#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cartesi-machine --append-rom-bootargs="single=yes" -- id 2>&1 | bash "$HERE/strip-ansi.sh" > "$out"
