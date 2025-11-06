FROM ubuntu:24.04

# OCI labels for GHCR metadata
LABEL org.opencontainers.image.source="https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker"
LABEL org.opencontainers.image.description="GNU/Hurd i386 microkernel development environment with QEMU"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y \
       qemu-system-i386 \
       qemu-utils \
       screen \
       telnet \
       curl \
       socat \
       expect \
       sshpass \
       netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/hurd-image

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9999

ENTRYPOINT ["/entrypoint.sh"]
