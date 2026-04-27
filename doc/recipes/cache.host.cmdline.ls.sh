#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
# docs:begin
cartesi-machine -- ls /bin > "$out" 2>&1
# docs:end
