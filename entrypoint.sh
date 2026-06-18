#!/bin/bash

NTFY_TOPIC="${NTFY_TOPIC:-NotifPort}"
BORE_SERVER="${BORE_SERVER:-bore.pub}"
SSH_PORT="${SSH_PORT:-22}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
  local title="$1" body="$2" priority="${3:-default}" tags="${4:-computer}"
  curl -s --max-time 5 -X POST "https://ntfy.sh/$NTFY_TOPIC" \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "Tags: $tags" \
    -d "$body" > /dev/null 2>&1 || true
}

log "========================================"
log "  VPS Railway - Ubuntu 20.04 + Bore"
log "========================================"

/usr/sbin/sshd
log "SSH daemon started"

notify "VPS Railway Starting..." "Ubuntu 20.04, menghubungkan bore tunnel..." "default" "rocket"

while true; do
  log "Menghubungkan ke $BORE_SERVER..."
  > /tmp/bore.log

  bore local "$SSH_PORT" --to "$BORE_SERVER" > /tmp/bore.log 2>&1 &
  BORE_PID=$!

  PORT=""
  for i in $(seq 1 30); do
    sleep 1
    PORT=$(grep -oE "${BORE_SERVER}:[0-9]+" /tmp/bore.log 2>/dev/null | head -1 | cut -d: -f2)
    [ -n "$PORT" ] && break
    [ -z "$PORT" ] && PORT=$(grep -iE "remote_port=[0-9]+" /tmp/bore.log 2>/dev/null | grep -oE "[0-9]+" | tail -1)
    [ -n "$PORT" ] && break
  done

  if [ -n "$PORT" ]; then
    log "========================================"
    log "  SSH TUNNEL READY"
    log "========================================"
    log "  ssh root@$BORE_SERVER -p $PORT"
    log "  Password: craxid"
    log "========================================"

    notify \
      "✅ VPS AKTIF! Port: $PORT" \
      "ssh root@bore.pub -p $PORT
Password: craxid" \
      "high" "computer,key"
  else
    log "ERROR: Gagal dapat port. Log:"
    cat /tmp/bore.log 2>/dev/null || true
    notify "⚠️ Bore GAGAL" "Tunnel gagal, cek log Railway." "urgent" "warning"
  fi

  wait $BORE_PID 2>/dev/null || true
  log "Bore disconnect. Reconnect dalam 5 detik..."
  notify "🔄 Reconnecting..." "bore putus, mencoba ulang..." "low" "arrows_counterclockwise"
  sleep 5
done &

log "HTTP health check port 8080"
exec python3 -c "
import http.server, socketserver
h = http.server.SimpleHTTPRequestHandler
h.log_message = lambda *a: None
socketserver.TCPServer(('', 8080), h).serve_forever()
"
