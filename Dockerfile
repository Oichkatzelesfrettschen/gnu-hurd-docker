FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    qemu-system-i386 \
    qemu-utils \
    screen \
    telnet \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/hurd-image

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9999

ENTRYPOINT ["/entrypoint.sh"]
