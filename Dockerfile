FROM debian
ARG NGROK_TOKEN
ARG REGION=ap
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt upgrade -y && apt install -y \
    ssh wget unzip vim curl python3
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok-stable-linux-amd64.zip \
    && cd / && unzip ngrok-stable-linux-amd64.zip \
    && chmod +x ngrok
RUN mkdir -p /run/sshd \
    && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config \
    && echo root:craxid | chpasswd \
    && ssh-keygen -A \
    && printf '#!/bin/bash\nNTFY_TOPIC="rairu-winsdevcltr09"\necho "Starting ngrok..."\n/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION:-ap}" 22 &\nsleep 6\nSSH_INFO=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null)\nif echo "$SSH_INFO" | grep -q "public_url"; then\n  PUBLIC_URL=$(echo "$SSH_INFO" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t[chr(116)+chr(117)+chr(110)+chr(110)+chr(101)+chr(108)+chr(115)][0][chr(112)+chr(117)+chr(98)+chr(108)+chr(105)+chr(99)+chr(95)+chr(117)+chr(114)+chr(108)])")\n  HOST=$(echo "$PUBLIC_URL" | sed "s/tcp:\\/\\///" | cut -d: -f1)\n  PORT=$(echo "$PUBLIC_URL" | sed "s/tcp:\\/\\///" | cut -d: -f2)\n  echo "========================================="\n  echo "SSH VPS Railway AKTIF!"\n  echo "  ssh root@$HOST -p $PORT"\n  echo "  Password: craxid"\n  echo "========================================="\n  MSG="ssh root@$HOST -p $PORT\nPassword: craxid"\n  curl -s -X POST "https://ntfy.sh/$NTFY_TOPIC" -H "Title: SSH VPS Railway Aktif" -H "Priority: high" -H "Tags: computer,key" -d "$MSG" > /dev/null 2>&1\n  echo "Notifikasi terkirim ke ntfy.sh/$NTFY_TOPIC"\nelse\n  echo "ERROR: Ngrok gagal. Cek NGROK_TOKEN."\n  curl -s -X POST "https://ntfy.sh/$NTFY_TOPIC" -H "Title: SSH VPS ERROR" -H "Priority: urgent" -H "Tags: warning" -d "Ngrok gagal. Cek token di Railway dashboard." > /dev/null 2>&1\nfi\n/usr/sbin/sshd -D\n' > /entrypoint.sh \
    && chmod +x /entrypoint.sh
EXPOSE 22
CMD ["/entrypoint.sh"]
