ARG TAG=0.20.0
ARG GUEST_TOOLS_VERSION=v0.18.0-test2
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

COPY tests/dependencies tests/dependencies.sha256 /tmp/cartesi-images/
RUN cd /tmp/cartesi-images && \
    mkdir -p build/images && \
    wget -nc -i dependencies -P build/images && \
    sha256sum --check dependencies.sha256 && \
    cd /usr/share/cartesi-machine/images && \
    mv /tmp/cartesi-images/build/images/* . && \
    ln -s "$(ls rootfs-tools*.ext2)" rootfs.ext2 && \
    ln -s "$(ls linux-*.bin)" linux.bin

ENV DEV_ENV_HAS_DOCGEN=yes
ENV PATH=/work/recipes:${PATH}
