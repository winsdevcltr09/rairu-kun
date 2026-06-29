#!/bin/bash

NTFY_TOPIC="${NTFY_TOPIC:-NotifPortxyz}"
ROOT_PASS="${ROOT_PASS:-craxid}"
CF_HOST="methatech.eu.org"
CF_SSH_HOST="ssh.methatech.eu.org"

export TUNNEL_TOKEN="${TUNNEL_TOKEN:-${CLOUDFLARE_TUNNEL_TOKEN:-}}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
  local title="$1" body="$2" priority="${3:-default}" tags="${4:-computer}"
  curl -s --max-time 10 -X POST "https://ntfy.sh/$NTFY_TOPIC" \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "Tags: $tags" \
    -d "$body" > /dev/null 2>&1 || true
}

token_status() {
  [ -n "$TUNNEL_TOKEN" ] && echo "SET" || echo "EMPTY"
}

setup_firewall() {
  log "=== Firewall ==="
  if ! iptables -L INPUT -n > /dev/null 2>&1; then
    log "iptables tidak tersedia — dilewati"
    return 0
  fi
  iptables -F INPUT 2>/dev/null || true
  iptables -F FORWARD 2>/dev/null || true
  iptables -P INPUT DROP 2>/dev/null || true
  iptables -P FORWARD DROP 2>/dev/null || true
  iptables -P OUTPUT ACCEPT 2>/dev/null || true
  iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT 2>/dev/null || true
  log "Firewall aktif"
}

bore_tunnel() {
  log "=== Bore Tunnel (SSH langsung, tanpa install di client) ==="
  while true; do
    log "Menghubungkan bore ke bore.pub..."
    > /tmp/bore.log

    bore local 22 --to bore.pub 2>&1 | tee /tmp/bore.log &
    BORE_PID=$!

    # Tangkap port dari output bore (tunggu max 30 detik)
    local port=""
    local i=0
    while [ $i -lt 30 ]; do
      sleep 1
      i=$((i + 1))
      port=$(grep -oP 'listening at bore\.pub:\K[0-9]+' /tmp/bore.log 2>/dev/null | head -1)
      [ -n "$port" ] && break
      # Fallback: cari pola port lain
      port=$(grep -oP '(?<=:)[0-9]{4,5}' /tmp/bore.log 2>/dev/null | head -1)
      [ -n "$port" ] && break
    done

    if [ -n "$port" ]; then
      log "Bore aktif! Port: $port"
      notify "SSH SIAP (Termux/HP)" "Tidak perlu install apapun!

Perintah SSH (copy paste langsung):
ssh root@bore.pub -p $port

Password: $ROOT_PASS

Catatan: port berubah jika VPS restart" "high" "iphone,key,tada"
    else
      log "Bore gagal dapat port. Log:"
      head -10 /tmp/bore.log | while read -r line; do log "  $line"; done
      notify "Bore Gagal" "Gagal konek bore.pub. Retry 30s..." "low" "warning"
    fi

    wait $BORE_PID 2>/dev/null || true
    log "Bore disconnect. Reconnect 15s..."
    sleep 15
  done
}

cloudflare_tunnel() {
  log "=== Cloudflare Tunnel ==="
  if [ -z "$TUNNEL_TOKEN" ]; then
    log "TUNNEL_TOKEN kosong — Cloudflare tunnel dilewati"
    return 0
  fi

  while true; do
    log "Menjalankan cloudflared tunnel run"
    > /tmp/cloudflared.log
    cloudflared tunnel run 2>&1 | tee /tmp/cloudflared.log &
    CF_PID=$!

    local ready=0
    local i=0
    while [ $i -lt 60 ]; do
      sleep 1; i=$((i + 1))
      if grep -qiE "Registered tunnel connection|registered connection" /tmp/cloudflared.log 2>/dev/null; then
        ready=1; log "Cloudflare tunnel terhubung (${i}s)"; break
      fi
    done

    if [ "$ready" = "1" ]; then
      notify "Cloudflare Tunnel Aktif" "SSH via domain (perlu cloudflared di client):
ssh root@${CF_SSH_HOST}

HTTP: https://${CF_HOST}" "default" "cloud"
    fi

    wait $CF_PID 2>/dev/null || true
    log "Cloudflare tunnel disconnect. Reconnect 10s..."
    sleep 10
  done
}

monitor_loop() {
  while true; do
    sleep 300
    local UPTIME MEM BORE_PORT
    UPTIME=$(uptime -p 2>/dev/null || echo 'n/a')
    MEM=$(free -m 2>/dev/null | awk '/Mem:/{printf "%dMB/%dMB", $3, $2}' || echo 'n/a')
    BORE_PORT=$(grep -oP 'listening at bore\.pub:\K[0-9]+' /tmp/bore.log 2>/dev/null | tail -1 || echo '?')
    notify "VPS Status" "Up: $UPTIME | RAM: $MEM
SSH: ssh root@bore.pub -p $BORE_PORT" "min" "bar_chart"
  done
}

# ======================================
log "====================================="
log "  Ubuntu VPS | Bore + Cloudflare"
log "  ntfy  : $NTFY_TOPIC"
log "  Token : $(token_status)"
log "====================================="

notify "VPS Starting..." "Boot sedang berjalan..." "default" "rocket"

echo "root:${ROOT_PASS}" | chpasswd 2>/dev/null || true
/usr/sbin/sshd && log "SSH daemon started"
setup_firewall

python3 -c "
import http.server, socketserver, threading, time
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(b'VPS Online')
threading.Thread(target=lambda: socketserver.TCPServer(('',80),H).serve_forever(), daemon=True).start()
time.sleep(86400)
" &

sleep 2

bore_tunnel &
cloudflare_tunnel &
monitor_loop &

log "Health check aktif di port 8080"
exec python3 -c "
import http.server, socketserver
h = http.server.SimpleHTTPRequestHandler
h.log_message = lambda *a: None
socketserver.TCPServer(('', 8080), h).serve_forever()
"
