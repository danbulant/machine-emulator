#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
remote-cartesi-machine --server-address=localhost:8080 > /dev/null 2>&1 &
while ! netstat -ntl 2>&1 | grep 8080 > /dev/null; do sleep 1; done
cartesi-machine \
    --remote-address=localhost:8080 \
    --checkin-address=localhost:8081 \
    --remote-shutdown \
    --max-mcycle=1Mi \
    -- echo "Still here!" 2>&1 | bash "$HERE/strip-ansi.sh" > "$out"
