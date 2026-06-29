#!/bin/bash

NTFY_TOPIC="${NTFY_TOPIC:-NotifPortxyz}"
ROOT_PASS="${ROOT_PASS:-craxid}"
CF_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"
CF_HOST="methatech.eu.org"
CF_SSH_HOST="ssh.methatech.eu.org"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
  local title="$1" body="$2" priority="${3:-default}" tags="${4:-computer}"
  curl -s --max-time 10 -X POST "https://ntfy.sh/$NTFY_TOPIC" \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "Tags: $tags" \
    -d "$body" > /dev/null 2>&1 || true
}

setup_firewall() {
  log "=== Mengaktifkan Firewall ==="
  if ! iptables -L INPUT -n > /dev/null 2>&1; then
    log "⚠️  iptables tidak tersedia (container tidak privileged) — firewall dilewati"
    notify "⚠️ Firewall Info" "Container tidak mendukung iptables (unprivileged mode).\nVPS tetap berjalan normal." "low" "information_source"
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
  iptables -A INPUT -p tcp --dport 23 -j DROP 2>/dev/null || true
  iptables -A INPUT -p tcp --dport 3389 -j DROP 2>/dev/null || true
  log "✅ Firewall aktif: SSH/HTTP/HTTPS/ICMP dibuka, port berbahaya diblokir"
  notify "🔥 Firewall Aktif" "iptables rules loaded:\n✅ SSH (22)\n✅ HTTP (80)\n✅ HTTPS (443)\n🛡️ Telnet/RDP diblokir" "default" "lock,shield"
}

cloudflare_tunnel() {
  log "=== Memulai Cloudflare Tunnel ==="

  if [ -z "$CF_TOKEN" ]; then
    log "❌ CLOUDFLARE_TUNNEL_TOKEN tidak diset! Set variabel env terlebih dahulu."
    notify "❌ Cloudflare Tunnel Gagal" "CLOUDFLARE_TUNNEL_TOKEN belum diset di Railway.\nTambahkan env variable di dashboard Railway." "urgent" "x,warning"
    return 1
  fi

  while true; do
    log "🔄 Menghubungkan ke Cloudflare Tunnel..."
    > /tmp/cloudflared.log
    cloudflared tunnel run --token "$CF_TOKEN" --no-autoupdate \
      2>&1 | tee /tmp/cloudflared.log &
    CF_PID=$!

    # Tunggu tunnel siap (max 90 detik)
    local ready=0
    for i in $(seq 1 90); do
      sleep 1
      if grep -qiE "Connection registered|Registered tunnel|conns=1|Connected to|connection registered|registered connection" /tmp/cloudflared.log 2>/dev/null; then
        ready=1
        break
      fi
      # Deteksi error fatal agar cepat retry
      if grep -qiE "invalid token|failed to unmarshal|error parsing" /tmp/cloudflared.log 2>/dev/null; then
        log "❌ Token tidak valid. Cek CLOUDFLARE_TUNNEL_TOKEN di Railway."
        break
      fi
    done

    if [ "$ready" = "1" ]; then
      log "✅ Cloudflare Tunnel AKTIF → $CF_HOST"
      local UPTIME=$(uptime -p 2>/dev/null || echo 'running')
      local BODY="🖥️ Ubuntu 20.04 VPS AKTIF via Cloudflare Tunnel

🔑 SSH    : ssh root@${CF_SSH_HOST} -o ProxyCommand='cloudflared access ssh --hostname %h'
🔒 Pass   : ${ROOT_PASS}
🌐 HTTP   : https://${CF_HOST}
📋 SSH Config:

Host ${CF_SSH_HOST}
    ProxyCommand cloudflared access ssh --hostname %h
    User root

⏰ Up: $UPTIME"
      notify "✅ VPS ONLINE via Cloudflare!" "$BODY" "high" "computer,key,white_check_mark,cloud"
    else
      log "⚠️ Tunnel belum terdeteksi ready, tapi tetap jalan..."
      log "Log cloudflared: $(head -20 /tmp/cloudflared.log 2>/dev/null)"
      notify "⚠️ Cloudflare Tunnel" "Tunnel mungkin sudah terhubung. Cek log untuk detail." "default" "warning"
    fi

    wait $CF_PID 2>/dev/null || true
    log "🔄 Cloudflare tunnel disconnect. Reconnect 10s..."
    notify "🔄 Reconnecting Cloudflare" "Tunnel terputus. Menghubungkan ulang dalam 10 detik..." "low" "arrows_counterclockwise"
    sleep 10
  done
}

monitor_loop() {
  local check_interval=300
  while true; do
    sleep $check_interval
    local UPTIME=$(uptime -p 2>/dev/null || echo 'running')
    local MEM=$(free -m 2>/dev/null | awk '/Mem:/{printf "%dMB / %dMB", $3, $2}' || echo 'n/a')
    local CF_STATUS="AKTIF"
    pgrep -f "cloudflared" > /dev/null || CF_STATUS="MATI"
    notify "📊 VPS Status (5 menit)" "⏰ Uptime: $UPTIME\n💾 RAM: $MEM\n☁️ Cloudflare: $CF_STATUS\n🌐 SSH: ${CF_SSH_HOST}" "min" "bar_chart"
  done
}

# ======================================
log "========================================"
log "  Ubuntu 20.04 VPS | Cloudflare Tunnel"
log "  Host   : $CF_HOST"
log "  SSH    : $CF_SSH_HOST"
log "  ntfy   : $NTFY_TOPIC"
log "========================================"

notify "🚀 VPS Starting..." "Ubuntu 20.04 sedang boot via Cloudflare Tunnel...\nHost: ${CF_HOST}\nntfy topic: $NTFY_TOPIC" "default" "rocket"

# Set password root
echo "root:${ROOT_PASS}" | chpasswd 2>/dev/null || true

# Start SSH daemon
/usr/sbin/sshd && log "SSH daemon started"

# Setup firewall
setup_firewall

# HTTP placeholder di port 80 untuk healthcheck internal
python3 - << 'PY' &
import http.server, socketserver, threading, time
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(b'VPS Ready - Connect via SSH: ssh.methatech.eu.org')
for p in [80]:
    threading.Thread(target=lambda p=p: socketserver.TCPServer(('',p),H).serve_forever(), daemon=True).start()
time.sleep(86400)
PY

sleep 2

# Jalankan Cloudflare tunnel
cloudflare_tunnel &

# Monitor status setiap 5 menit
monitor_loop &

log "Health check port 8080"
exec python3 -c "
import http.server, socketserver
h=http.server.SimpleHTTPRequestHandler
h.log_message=lambda *a:None
socketserver.TCPServer(('',8080),h).serve_forever()
"
