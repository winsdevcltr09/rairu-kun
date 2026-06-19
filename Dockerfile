FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive \
    NTFY_TOPIC=NotifPortxyz \
    BORE_SERVER=bore.pub \
    ROOT_PASS=craxid \
    SSH_PORT=22

RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server curl python3 vim sudo net-tools wget htop git unzip \
        iptables iproute2 iputils-ping procps && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Download bore binary from GitHub releases
RUN BORE_VERSION=$(curl -s https://api.github.com/repos/ekzhang/bore/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v') && \
    echo "Installing bore v${BORE_VERSION}" && \
    curl -fsSL "https://github.com/ekzhang/bore/releases/download/v${BORE_VERSION}/bore-v${BORE_VERSION}-x86_64-unknown-linux-musl.tar.gz" -o /tmp/bore.tar.gz && \
    tar -xzf /tmp/bore.tar.gz -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/bore && \
    rm /tmp/bore.tar.gz && \
    bore --version

RUN mkdir -p /run/sshd && \
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

EXPOSE 22 80 443 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD pgrep sshd > /dev/null || exit 1

CMD ["/entrypoint.sh"]
