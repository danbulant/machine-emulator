#!/bin/bash
outs=(
    "$CACHE_DIR/host.lua.remote-server.out"
    "$CACHE_DIR/host.lua.remote-client.out"
)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
cd "$HERE"
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
    config.nothing-to-do 2>&1 | bash "$HERE/strip-ansi.sh" > "$out_client"
wait "$srv_pid"
bash "$HERE/strip-ansi.sh" < "$srv_tmp" > "$out_server"
