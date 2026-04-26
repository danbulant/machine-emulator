#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-client.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
sed -n '31,52p' "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-client.out" > "$out"
