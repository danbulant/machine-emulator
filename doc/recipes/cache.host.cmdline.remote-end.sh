#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out_server="$CACHE_DIR/host.cmdline.remote-begin-end-server.out"
out_client="$CACHE_DIR/host.cmdline.remote-end-client.out"
srv_tmp=$(mktemp)
remote-cartesi-machine --server-address=localhost:8080 > "$srv_tmp" 2>&1 &
srv_pid=$!
while ! netstat -ntl 2>&1 | grep 8080 > /dev/null; do sleep 1; done
cartesi-machine \
    --remote-address=localhost:8080 \
    --checkin-address=localhost:8081 \
    --no-remote-destroy \
    --max-mcycle=1Mi \
    -- echo "Still here!" > /dev/null 2>&1
cartesi-machine \
    --remote-address=localhost:8080 \
    --checkin-address=localhost:8081 \
    --remote-shutdown \
    --no-remote-create 2>&1 | bash "$HERE/strip-ansi.sh" > "$out_client"
wait "$srv_pid"
bash "$HERE/strip-ansi.sh" < "$srv_tmp" > "$out_server"
rm -f "$srv_tmp"
