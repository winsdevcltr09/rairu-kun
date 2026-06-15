#!/bin/bash
NTFY_TOPIC="rairu-winsdevcltr09"

echo "Starting ngrok..."
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION:-ap}" 22 &
sleep 6

SSH_INFO=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null)
if echo "$SSH_INFO" | grep -q "public_url"; then
  PUBLIC_URL=$(echo "$SSH_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin)['tunnels'][0]['public_url'])")
  HOST=$(echo "$PUBLIC_URL" | sed "s/tcp:\/\///" | cut -d: -f1)
  PORT=$(echo "$PUBLIC_URL" | sed "s/tcp:\/\///" | cut -d: -f2)
  echo "========================================="
  echo "SSH VPS Railway AKTIF!"
  echo "  ssh root@$HOST -p $PORT"
  echo "  Password: craxid"
  echo "========================================="
  curl -s -X POST "https://ntfy.sh/$NTFY_TOPIC" \
    -H "Title: SSH VPS Railway Aktif" \
    -H "Priority: high" \
    -H "Tags: computer,key" \
    -d "ssh root@$HOST -p $PORT
Password: craxid" > /dev/null 2>&1
  echo "Notifikasi terkirim ke ntfy.sh/$NTFY_TOPIC"
else
  echo "ERROR: Ngrok gagal. Cek NGROK_TOKEN."
  curl -s -X POST "https://ntfy.sh/$NTFY_TOPIC" \
    -H "Title: SSH VPS Railway ERROR" \
    -H "Priority: urgent" \
    -H "Tags: warning" \
    -d "Ngrok gagal konek. Cek token NGROK di Railway dashboard." > /dev/null 2>&1
fi

/usr/sbin/sshd -D

