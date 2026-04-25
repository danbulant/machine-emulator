#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out_server="$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-server.out"
out_client="$CACHE_DIR/host.cmdline.rolling-ioctl-echo-loop-client.out"
(cd "$HERE" && {
    for i in 1 2; do
        rollup-memory-range encode input-metadata > epoch-0-input-metadata-$i.bin <<-EOFENC
        {
            "msg_sender": $(printf '"0x%040d"' $i)
            "block_number": 0,
            "time_stamp": 0,
            "epoch_index": 0,
            "input_index": $i
        }
EOFENC
        rollup-memory-range encode input > epoch-0-input-$i.bin <<-EOFENC
        {
            "payload": "hello from input $i"
        }
EOFENC
    done
    rollup-memory-range encode input > query.bin <<'EOFQ'
{
    "payload": "hello from query"
}
EOFQ
    echo "Done creating bins"
    srv_tmp=$(mktemp)
    remote-cartesi-machine --server-address=localhost:8080 > "$srv_tmp" 2>&1 &
    srv_pid=$!
    while ! netstat -ntl 2>&1 | grep 8080 > /dev/null; do sleep 1; done
    cartesi-machine \
        --remote-address=localhost:8080 \
        --checkin-address=localhost:8081 \
        --remote-shutdown \
        --rollup \
        --rollup-advance-state=epoch_index:0,input_index_begin:1,input_index_end:3,hashes \
        --rollup-inspect-state \
        -- ioctl-echo-loop --vouchers=1 --notices=1 --reports=1 --reject=1 \
        2>&1 | bash "$HERE/strip-ansi.sh" > "$out_client"
    wait "$srv_pid"
    bash "$HERE/strip-ansi.sh" < "$srv_tmp" > "$out_server"
    rm -f "$srv_tmp"
    rm -rf epoch-0-input-1.bin epoch-0-input-1-notice-0.bin epoch-0-input-1-notice-hashes.bin \
           epoch-0-input-1-report-0.bin epoch-0-input-1-voucher-0.bin epoch-0-input-1-voucher-hashes.bin \
           epoch-0-input-2.bin epoch-0-input-2-notice-0.bin epoch-0-input-2-notice-hashes.bin \
           epoch-0-input-2-report-0.bin epoch-0-input-2-voucher-0.bin epoch-0-input-2-voucher-hashes.bin \
           epoch-0-input-metadata-1.bin epoch-0-input-metadata-2.bin query.bin query-report-0.bin
})
