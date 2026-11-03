# syntax=docker/dockerfile:1
FROM debian:trixie-slim

# TLS trust is supplied by the managed environment at build time, not baked in.
RUN --mount=type=secret,id=system_ca,required=true \
    apt-get -o Acquire::https::CaInfo=/run/secrets/system_ca update && \
    apt-get -o Acquire::https::CaInfo=/run/secrets/system_ca install -y --no-install-recommends \
      ca-certificates build-essential clang cmake curl git libgtk-3-dev liblzma-dev \
      libsecret-1-dev ninja-build pkg-config unzip xz-utils \
      xvfb xauth xdotool imagemagick python3 && \
    rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 1000 --shell /bin/bash viewer
ENV HOME=/home/viewer \
    PUB_CACHE=/home/viewer/.pub-cache \
    CARGO_HOME=/home/viewer/.cargo \
    RUSTUP_HOME=/home/viewer/.rustup \
    PATH=/home/viewer/.cargo/bin:/opt/viewer/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER viewer
WORKDIR /project
CMD ["sleep", "infinity"]
