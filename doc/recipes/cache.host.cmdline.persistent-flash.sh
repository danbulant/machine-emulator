#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$@"
trap 'rm -rf foo foo.tar foo.ext2' EXIT
rm -rf foo
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
genext2fs -f -b 1024 -a foo.tar foo.ext2
# docs:begin
cartesi-machine \
    --flash-drive="label:foo,filename:foo.ext2" \
    -- "ls /mnt/foo/*.txt && cp /mnt/foo/bar.txt /mnt/foo/baz.txt && ls /mnt/foo/*.txt" \
    > "$out" 2>&1
# docs:end
