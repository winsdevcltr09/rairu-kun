FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive \
    NTFY_TOPIC=NotifPortxyz \
    CLOUDFLARE_TUNNEL_TOKEN="" \
    ROOT_PASS=craxid \
    SSH_PORT=22

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates openssh-server curl python3 vim sudo net-tools wget htop git unzip \
        iptables iproute2 iputils-ping procps passwd && \
    update-ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
        -o /usr/local/bin/cloudflared && \
    chmod +x /usr/local/bin/cloudflared && \
    cloudflared --version

# Install bore (SSH langsung tanpa install di client)
RUN curl -fsSL "https://github.com/ekzhang/bore/releases/latest/download/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz" \
        -o /tmp/bore.tar.gz && \
    tar -xzf /tmp/bore.tar.gz -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/bore && \
    rm /tmp/bore.tar.gz

RUN mkdir -p /run/sshd && \
    echo "root:craxid" | chpasswd && \
    ssh-keygen -A

RUN sed -i \
    -e 's/#PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' \
    -e 's/#PasswordAuthentication yes/PasswordAuthentication yes/' \
    -e 's/PasswordAuthentication no/PasswordAuthentication yes/' \
    -e 's/#ClientAliveInterval.*/ClientAliveInterval 60/' \
    -e 's/#ClientAliveCountMax.*/ClientAliveCountMax 10/' \
    /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD pgrep sshd > /dev/null || exit 1

CMD ["/entrypoint.sh"]
