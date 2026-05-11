#!/bin/sh
set -eu
TAG=${TAG:-devel}

# Cross-compile the dapp and assemble the rootfs as a flattened tarball.
docker buildx build --platform=linux/riscv64 \
    --output type=tar,dest=hello-rootfs.tar \
    -f Dockerfile.hello-rootfs .

# Convert the tarball into an ext2 image using xgenext2fs from the docs image.
docker run --rm -v "$(pwd)":/work -w /work \
    cartesi/machine-emulator-docs:"$TAG" \
    xgenext2fs -fzB 4096 -i 4096 -r +50000 \
        -a hello-rootfs.tar -L hello hello-rootfs.ext2
