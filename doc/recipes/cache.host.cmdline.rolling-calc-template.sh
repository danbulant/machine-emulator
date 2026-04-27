#!/bin/bash
outs=(
    "$CACHE_DIR/host.cmdline.rolling-calc-template.template.out"
    "$CACHE_DIR/host.cmdline.rolling-calc-template.server.out"
    "$CACHE_DIR/host.cmdline.rolling-calc-template.client.out"
)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
out_template="${outs[0]}"
out_server="${outs[1]}"
out_client="${outs[2]}"
srv_tmp=$(mktemp)
_cleanup() {
    rm -f "$srv_tmp" \
        epoch-0-input-metadata-1.bin epoch-0-input-1.bin \
        epoch-0-input-metadata-2.bin epoch-0-input-2.bin \
        epoch-0-input-1-notice-hashes.bin epoch-0-input-1-voucher-hashes.bin \
        epoch-0-input-2-notice-0.bin epoch-0-input-2-notice-hashes.bin \
        epoch-0-input-2-voucher-hashes.bin \
        calc.tar calc.ext2
    rm -rf calc calc-template
}
trap _cleanup EXIT
rollup-memory-range encode input-metadata > epoch-0-input-metadata-1.bin \
    < <(printf '{\n    "msg_sender": "0x%040d",\n    "block_number": 0,\n    "time_stamp": 0,\n    "epoch_index": 0,\n    "input_index": 1\n}\n' 1)
rollup-memory-range encode input > epoch-0-input-1.bin \
    < <(printf '{\n    "payload": "invalid input"\n}\n')
rollup-memory-range encode input-metadata > epoch-0-input-metadata-2.bin \
    < <(printf '{\n    "msg_sender": "0x%040d",\n    "block_number": 0,\n    "time_stamp": 0,\n    "epoch_index": 0,\n    "input_index": 2\n}\n' 2)
rollup-memory-range encode input > epoch-0-input-2.bin \
    < <(printf '{\n    "payload": "6*2^1024 + 3*2^512"\n}\n')
rm -rf calc && mkdir calc && cp -f calc.sh calc && chmod +x calc/calc.sh
tar --sort=name --mtime="2022-01-01" --owner=1000 --group=1000 --numeric-owner \
    -cf calc.tar --directory=calc .
rm -rf calc
genext2fs -f -b 1024 -a calc.tar calc.ext2
rm -rf calc-template
cartesi-machine \
    --rollup \
    --flash-drive=label:calc,filename:calc.ext2 \
    --store="calc-template" \
    -- /mnt/calc/calc.sh > "$out_template" 2>&1
remote-cartesi-machine --server-address=localhost:8080 > "$srv_tmp" 2>&1 &
srv_pid=$!
while ! netstat -ntl 2>&1 | grep 8080 > /dev/null; do sleep 1; done
cartesi-machine \
    --remote-address=localhost:8080 \
    --checkin-address=localhost:8081 \
    --remote-shutdown \
    --rollup \
    --rollup-advance-state=epoch_index:0,input_index_begin:1,input_index_end:3,hashes \
    --load="calc-template" \
    > "$out_client" 2>&1
wait "$srv_pid"
mv "$srv_tmp" "$out_server"
