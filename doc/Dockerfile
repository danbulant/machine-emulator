ARG TAG=devel
FROM cartesi/machine-emulator:$TAG

USER root

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y make pandoc net-tools genext2fs && \
    rm -rf /var/lib/apt/lists/*

# Expose doc/-local images at the emulator's default search path.
# /work is the documentation source mounted at container run time.
RUN mkdir -p /usr/share/cartesi-machine/images && \
    ln -sf /work/linux.bin  /usr/share/cartesi-machine/images/linux.bin && \
    ln -sf /work/rom.bin    /usr/share/cartesi-machine/images/rom.bin && \
    ln -sf /work/rootfs.ext2 /usr/share/cartesi-machine/images/rootfs.ext2

ENV DEV_ENV_HAS_DOCGEN=yes
