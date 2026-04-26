#!/bin/bash
outs=(
    "$CACHE_DIR/host.cmdline.remote-server.out"
    "$CACHE_DIR/host.cmdline.remote-client.out"
)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
out_server="${outs[0]}"
out_client="${outs[1]}"
srv_tmp=$(mktemp)
remote-cartesi-machine --server-address=localhost:8080 > "$srv_tmp" 2>&1 &
srv_pid=$!
while ! netstat -ntl 2>&1 | grep 8080 > /dev/null; do sleep 1; done
cartesi-machine \
    --remote-address=localhost:8080 \
    --checkin-address=localhost:8081 \
    --remote-shutdown > "$out_client" 2>&1
wait "$srv_pid"
mv "$srv_tmp" "$out_server"
