#!/bin/bash
reads=("$CACHE_DIR/host.lua.config-dump-nothing.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
lua find-htif-putchar.lua >/dev/null 2>"$out"
