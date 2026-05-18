ARG TAG=0.20.0
ARG GUEST_TOOLS_VERSION=v0.18.0-test3
ARG GENEXT2FS_VERSION=v1.5.6

FROM cartesi/machine-emulator:$TAG AS hex-builder
ARG GUEST_TOOLS_VERSION
USER root
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y --no-install-recommends g++ wget ca-certificates && \
    wget -qO- https://github.com/cartesi/machine-guest-tools/archive/refs/tags/$GUEST_TOOLS_VERSION.tar.gz \
        | tar -xz -C /tmp --wildcards --strip-components=3 '*/sys-utils/hex/hex.cpp' && \
    g++ -O2 -o /usr/local/bin/hex /tmp/hex.cpp

FROM cartesi/machine-emulator:$TAG AS xgenext2fs-builder
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
        bc devio device-tree-compiler e2tools file jq libarchive13 lua-dkjson wget && \
    rm -rf /var/lib/apt/lists/*

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
