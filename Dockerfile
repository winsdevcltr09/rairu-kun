FROM debian
ARG NGROK_TOKEN
ARG REGION=ap
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt upgrade -y && apt install -y \
    ssh wget unzip vim curl python3
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok-stable-linux-amd64.zip\
    && cd / && unzip ngrok-stable-linux-amd64.zip \
    && chmod +x ngrok
RUN mkdir -p /run/sshd \
    && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config \
    && echo root:craxid | chpasswd \
    && ssh-keygen -A
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 22
CMD ["/entrypoint.sh"]

