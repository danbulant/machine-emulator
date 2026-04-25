ARG TAG=0.5.0
FROM cartesi/playground:$TAG

USER root

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y make pandoc && \
    rm -rf /var/lib/apt/lists/*

ENV DEV_ENV_HAS_DOCGEN=yes
