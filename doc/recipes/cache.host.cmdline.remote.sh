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
    --remote-shutdown 2>&1 | bash "$HERE/strip-ansi.sh" > "$out_client"
wait "$srv_pid"
bash "$HERE/strip-ansi.sh" < "$srv_tmp" > "$out_server"
rm -f "$srv_tmp"
