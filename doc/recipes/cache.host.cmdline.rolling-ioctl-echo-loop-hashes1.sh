#!/bin/bash
reads=("$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-client.out")
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cat "$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-client.out"     | bash "$HERE/all-hashes.sh"     | sed -n '2p'     | bash "$HERE/trunc8.sh" > "$out"
