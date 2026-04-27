#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
trap 'rm -rf foo foo.tar foo.ext2' EXIT
rm -rf foo
# docs:begin setup
mkdir foo
echo "Hello world!" > foo/bar.txt
tar \
    --sort=name \
    --mtime="2022-01-01" \
    --owner=1000 \
    --group=1000 \
    --numeric-owner \
    -cf foo.tar \
    --directory=foo .
genext2fs \
    -f \
    -b 1024 \
    -a foo.tar \
    foo.ext2
# docs:end setup
# docs:begin run
cartesi-machine \
    --flash-drive="label:foo,filename:foo.ext2" \
    -- "cat /mnt/foo/bar.txt" \
    > "$out" 2>&1
# docs:end run
