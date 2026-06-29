#!/bin/bash

NTFY_TOPIC="${NTFY_TOPIC:-NotifPortxyz}"
ROOT_PASS="${ROOT_PASS:-craxid}"
CF_HOST="methatech.eu.org"
CF_SSH_HOST="ssh.methatech.eu.org"

# cloudflared membaca TUNNEL_TOKEN dari env secara otomatis
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
  if [ -n "$TUNNEL_TOKEN" ]; then
    echo "SET"
  else
    echo "EMPTY"
  fi
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

cloudflare_tunnel() {
  log "=== Cloudflare Tunnel ==="
  local status
  status=$(token_status)
  log "TUNNEL_TOKEN: $status"

  if [ -z "$TUNNEL_TOKEN" ]; then
    log "ERROR: TUNNEL_TOKEN kosong. Set CLOUDFLARE_TUNNEL_TOKEN di Railway."
    notify "ERROR Tunnel" "TUNNEL_TOKEN kosong. Set env CLOUDFLARE_TUNNEL_TOKEN di Railway." "urgent" "x"
    return 1
  fi

  while true; do
    log "Menjalankan: cloudflared tunnel run --no-autoupdate"
    > /tmp/cloudflared.log

    # TUNNEL_TOKEN sudah di-export, cloudflared baca otomatis
    cloudflared tunnel run --no-autoupdate 2>&1 | tee /tmp/cloudflared.log &
    CF_PID=$!

    local ready=0
    local i=0
    while [ $i -lt 120 ]; do
      sleep 1
      i=$((i + 1))

      if grep -qiE "Registered tunnel connection|registered connection|conns=[1-9]|Connection registered" /tmp/cloudflared.log 2>/dev/null; then
        ready=1
        log "Tunnel TERHUBUNG setelah ${i}s"
        break
      fi

      if grep -qiE "invalid token|bad token|failed to unmarshal|error parsing|unable to parse" /tmp/cloudflared.log 2>/dev/null; then
        log "ERROR: Token tidak valid!"
        kill $CF_PID 2>/dev/null || true
        notify "ERROR Token" "Token tidak valid. Cek CLOUDFLARE_TUNNEL_TOKEN di Railway." "urgent" "x"
        sleep 60
        break
      fi

      if [ $((i % 15)) -eq 0 ]; then
        log "Menunggu tunnel... ${i}s"
        tail -3 /tmp/cloudflared.log 2>/dev/null | while read -r line; do log "  > $line"; done
      fi
    done

    if [ "$ready" = "1" ]; then
      local UPTIME
      UPTIME=$(uptime -p 2>/dev/null || echo 'running')
      notify "VPS ONLINE" "Ubuntu VPS aktif via Cloudflare!

SSH: ssh root@${CF_SSH_HOST}
Pass: ${ROOT_PASS}
HTTP: https://${CF_HOST}

~/.ssh/config:
Host ${CF_SSH_HOST}
    ProxyCommand cloudflared access ssh --hostname %h
    User root

Up: $UPTIME" "high" "computer,key"
    else
      log "Tunnel tidak ready setelah timeout. Retry..."
    fi

    wait $CF_PID 2>/dev/null || true
    log "Tunnel disconnect. Reconnect 10s..."
    sleep 10
  done
}

monitor_loop() {
  while true; do
    sleep 300
    local UPTIME MEM CF_OK
    UPTIME=$(uptime -p 2>/dev/null || echo 'n/a')
    MEM=$(free -m 2>/dev/null | awk '/Mem:/{printf "%dMB/%dMB", $3, $2}' || echo 'n/a')
    CF_OK=$(pgrep -f "cloudflared" > /dev/null && echo "AKTIF" || echo "MATI")
    notify "VPS Status" "Up: $UPTIME | RAM: $MEM | CF: $CF_OK" "min" "bar_chart"
  done
}

# ======================================
log "====================================="
log "  Ubuntu VPS | Cloudflare Tunnel"
log "  Host  : $CF_HOST"
log "  SSH   : $CF_SSH_HOST"
log "  ntfy  : $NTFY_TOPIC"
log "  Token : $(token_status)"
log "====================================="

notify "VPS Starting..." "Boot via Cloudflare | ntfy: $NTFY_TOPIC" "default" "rocket"

echo "root:${ROOT_PASS}" | chpasswd 2>/dev/null || true
/usr/sbin/sshd && log "SSH daemon started"
setup_firewall

python3 -c "
import http.server, socketserver, threading, time
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(b'VPS Online - ssh.methatech.eu.org')
threading.Thread(target=lambda: socketserver.TCPServer(('',80),H).serve_forever(), daemon=True).start()
time.sleep(86400)
" &

sleep 2

cloudflare_tunnel &
monitor_loop &

log "Health check aktif di port 8080"
exec python3 -c "
import http.server, socketserver
h = http.server.SimpleHTTPRequestHandler
h.log_message = lambda *a: None
socketserver.TCPServer(('', 8080), h).serve_forever()
"
