#!/bin/sh
set -eu

# Generate a package and license report for rootfs-docs.ext2 in markdown,
# the same way machine-guest-tools does for its rootfs. Instead of
# rebuilding the rootfs docker image (which would require riscv64
# emulation), the committed ext2 is converted into a docker image with
# "docker import", which executes nothing. The report therefore describes
# the exact committed artifact. It goes to stdout, diagnostics to stderr.

image=cartesi/rootfs-docs

# The scanner resolves package lists against the same archive snapshot the
# image was built from, so source-package URIs stay stable over time.
APT_SNAPSHOT=$(sed -n 's/^ARG UBUNTU_SNAPSHOT=//p' Dockerfile.rootfs-docs)
export APT_SNAPSHOT

# scan-local.sh builds this same scanner image again later (cached). It is
# built here first because it is also where the ext2 is unpacked, by root,
# on a Linux filesystem, so ownership and permissions survive into the tar.
docker buildx build --load -t repo-info:local-dpkg \
    -f third-party/repo-info/Dockerfile.local-dpkg \
    third-party/repo-info 1>&2

docker run --rm -v "$PWD/rootfs-docs.ext2:/rootfs.ext2:ro" repo-info:local-dpkg \
    sh -c 'mkdir /x && debugfs -R "rdump / /x" /rootfs.ext2 1>&2 && \
           tar -C /x --exclude=./lost+found -cf - .' |
    docker import --platform linux/riscv64 - $image 1>&2

# Whether docker inspect can format scan-local.sh's metadata template for
# an imported image depends on the image store. The containerd store keeps
# a sparse config that fails the template (only its leading newline is
# printed), while the classic store renders the full section. Some of its
# fields are also not byte-stable across regenerations. The filter below
# drops the whole Docker Metadata section, restoring the blank line the
# failed template would have left, so the report comes out the same in
# both cases.
(cd third-party/repo-info && ./scan-local.sh $image linux/riscv64) |
    awk '
        /^## Docker Metadata$/ { skip = 1; next }
        skip && /^## / { skip = 0; print "" }
        !skip
    '
