#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cartesi-machine --append-rom-bootargs="single=yes" -- id > "$out" 2>&1
