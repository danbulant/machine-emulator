#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-client.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
sed -n '1,5p' "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-client.out" > "$out"
