#!/bin/bash
outs=(
    "$CACHE_DIR/host.lua.remote-server.out"
    "$CACHE_DIR/host.lua.remote-client.out"
)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
out_server="${outs[0]}"
out_client="${outs[1]}"
srv_tmp=$(mktemp)
trap 'rm -f "$srv_tmp"' EXIT
remote-cartesi-machine --server-address=localhost:8080 > "$srv_tmp" 2>&1 &
srv_pid=$!
while ! netstat -ntl 2>&1 | grep 8080 > /dev/null; do sleep 1; done
lua5.3 run-remote-config.lua \
    localhost:8080 \
    localhost:8081 \
    config.nothing-to-do > "$out_client" 2>&1
wait "$srv_pid"
mv "$srv_tmp" "$out_server"
