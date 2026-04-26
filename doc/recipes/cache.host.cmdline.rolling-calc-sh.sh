#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cat "$HERE/calc.sh" > "$out"
