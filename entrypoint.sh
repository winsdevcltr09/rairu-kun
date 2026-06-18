#!/bin/bash

NTFY_TOPIC="${NTFY_TOPIC:-NotifPort}"
BORE_SERVER="${BORE_SERVER:-bore.pub}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
  curl -s --max-time 5 -X POST "https://ntfy.sh/$NTFY_TOPIC" \
    -H "Title: $1" -H "Priority: $3" -H "Tags: $4" -d "$2" > /dev/null 2>&1 || true
}

bore_tunnel() {
  local lport="$1" label="$2" log_file="/tmp/bore_${1}.log"
  while true; do
    > "$log_file"
    bore local "$lport" --to "$BORE_SERVER" > "$log_file" 2>&1 &
    local PID=$!
    local PORT=""
    for i in $(seq 1 30); do
      sleep 1
      PORT=$(grep -oE "${BORE_SERVER}:[0-9]+" "$log_file" 2>/dev/null | head -1 | cut -d: -f2)
      [ -n "$PORT" ] && break
      [ -z "$PORT" ] && PORT=$(grep -iE "remote_port=[0-9]+" "$log_file" 2>/dev/null | grep -oE "[0-9]+" | tail -1)
      [ -n "$PORT" ] && break
    done
    if [ -n "$PORT" ]; then
      log "[$label] READY → bore.pub:$PORT"
      echo "$PORT" > "/tmp/port_${lport}.txt"
      update_summary
    else
      log "[$label] GAGAL: $(cat $log_file 2>/dev/null | head -3)"
    fi
    wait $PID 2>/dev/null || true
    log "[$label] Disconnect. Reconnect 5s..."
    rm -f "/tmp/port_${lport}.txt"
    sleep 5
  done
}

update_summary() {
  local P22=$(cat /tmp/port_22.txt 2>/dev/null)
  local P80=$(cat /tmp/port_80.txt 2>/dev/null)
  local P443=$(cat /tmp/port_443.txt 2>/dev/null)
  [ -z "$P22" ] && return
  local BODY="SSH : ssh root@bore.pub -p ${P22} (pass: craxid)"
  [ -n "$P80"  ] && BODY="$BODY
HTTP : bore.pub:${P80}"
  [ -n "$P443" ] && BODY="$BODY
HTTPS: bore.pub:${P443}"
  notify "✅ VPS AKTIF - Port Ready!" "$BODY" "high" "computer,key,lock"
}

log "========================================"
log "  Ubuntu 20.04 | Ports: 22+80+443"
log "========================================"

# Start SSH
/usr/sbin/sshd && log "SSH daemon started"

# Placeholder listener port 80 dan 443 agar bore bisa forward
python3 - << 'PY' &
import http.server, socketserver, threading, time
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(b'VPS Ready - Install your panel via SSH')
for p in [80, 443]:
    threading.Thread(target=lambda p=p: socketserver.TCPServer(('',p),H).serve_forever(), daemon=True).start()
time.sleep(86400)
PY

sleep 2
notify "VPS Railway Starting..." "Ubuntu 20.04 | Tunnel 22+80+443..." "default" "rocket"

# 3 bore tunnel paralel
bore_tunnel 22  "SSH-22"    &
bore_tunnel 80  "HTTP-80"   &
bore_tunnel 443 "HTTPS-443" &

log "Health check port 8080"
exec python3 -c "
import http.server, socketserver
h=http.server.SimpleHTTPRequestHandler
h.log_message=lambda *a:None
socketserver.TCPServer(('',8080),h).serve_forever()
"
