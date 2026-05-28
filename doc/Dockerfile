ARG TAG=0.20.0
ARG GUEST_TOOLS_VERSION=v0.18.0-test3
ARG GENEXT2FS_VERSION=v1.5.6
# Base for the host-tool builder stages below. These stages compile binaries
# that are copied into the final emulator-based image, so the base must stay
# ABI-compatible with cartesi/machine-emulator:$TAG. It deliberately does NOT
# reference $TAG, so bumping the emulator image reuses the builders' cache.
# The Makefile overrides this with the emulator image's own base, read from its
# io.cartesi.machine-emulator.base-image label, so it tracks automatically if
# the emulator rebases.
ARG BUILDER_BASE=debian:trixie-20250811-slim

FROM $BUILDER_BASE AS hex-builder
ARG GUEST_TOOLS_VERSION
USER root
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y --no-install-recommends g++ wget ca-certificates && \
    wget -qO- https://github.com/cartesi/machine-guest-tools/archive/refs/tags/$GUEST_TOOLS_VERSION.tar.gz \
        | tar -xz -C /tmp --wildcards --strip-components=3 '*/sys-utils/hex/hex.cpp' && \
    g++ -O2 -o /usr/local/bin/hex /tmp/hex.cpp

FROM $BUILDER_BASE AS xgenext2fs-builder
ARG GENEXT2FS_VERSION
USER root
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y --no-install-recommends \
        automake autotools-dev build-essential libarchive-dev wget ca-certificates && \
    wget -qO- https://github.com/cartesi/genext2fs/archive/refs/tags/$GENEXT2FS_VERSION.tar.gz \
        | tar -xz -C /tmp && \
    cd /tmp/genext2fs-* && \
    ./autogen.sh && \
    ./configure --enable-libarchive --prefix=/usr/local && \
    make -j"$(nproc)" install

FROM cartesi/machine-emulator:$TAG

USER root

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y \
        make pandoc \
        bash-completion bc devio device-tree-compiler e2tools file jq libarchive13 lua-dkjson wget && \
    rm -rf /var/lib/apt/lists/*

# Snapshot cartesi-machine's bash completion into the canonical dir, then enable
# the framework loader by uncommenting the block Debian ships (disabled) in
# /etc/bash.bashrc. The package's /etc/profile.d snippet only covers login
# shells; the playground runs a non-login shell, which reads only bash.bashrc.
# With the loader active, the file lazy-loads on first `cartesi-machine <TAB>`.
RUN cartesi-machine --bash-completion > /usr/share/bash-completion/completions/cartesi-machine && \
    sed -i '/^#if ! shopt -oq posix; then/,/^#fi$/ s/^#//' /etc/bash.bashrc

COPY --from=hex-builder /usr/local/bin/hex /usr/local/bin/hex
COPY --from=xgenext2fs-builder /usr/local/bin/xgenext2fs /usr/local/bin/xgenext2fs

RUN mkdir -p /tmp/cartesi-images/build/images && \
    cd /usr/share/cartesi-machine && \
    wget -nc -i dependencies -P /tmp/cartesi-images/build/images && \
    cd /tmp/cartesi-images && \
    cp /usr/share/cartesi-machine/dependencies.sha256 . && \
    sha256sum --check dependencies.sha256 && \
    cd /usr/share/cartesi-machine/images && \
    mv /tmp/cartesi-images/build/images/linux-*.bin . && \
    ln -s "$(ls linux-*.bin)" linux.bin && \
    rm -rf /tmp/cartesi-images

COPY recipes/rootfs-docs.ext2 /usr/share/cartesi-machine/images/rootfs-docs.ext2
RUN ln -s rootfs-docs.ext2 /usr/share/cartesi-machine/images/rootfs.ext2

ENV DEV_ENV_HAS_DOCGEN=yes
ENV PATH=/work/recipes:${PATH}

# Run as the host user: the entrypoint (carried dormant by the emulator image)
# reads the USER/UID/GID/GROUP env that run-docs-image / docs-image-exec pass
# and gosu-drops to it, so files written under /work are owned by the host user.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
