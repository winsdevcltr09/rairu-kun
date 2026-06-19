#!/bin/bash

NTFY_TOPIC="${NTFY_TOPIC:-NotifPortxyz}"
BORE_SERVER="${BORE_SERVER:-bore.pub}"
ROOT_PASS="${ROOT_PASS:-craxid}"

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
    notify "⚠️ Firewall Info" "Railway container tidak mendukung iptables (unprivileged mode).\nVPS tetap berjalan normal." "low" "information_source"
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
      PORT=$(grep -iE "remote_port=[0-9]+" "$log_file" 2>/dev/null | grep -oE "[0-9]+" | tail -1)
      [ -n "$PORT" ] && break
    done
    if [ -n "$PORT" ]; then
      log "[$label] READY → bore.pub:$PORT"
      echo "$PORT" > "/tmp/port_${lport}.txt"
      update_summary
    else
      log "[$label] GAGAL: $(cat $log_file 2>/dev/null | head -3)"
      notify "⚠️ Tunnel Gagal [$label]" "Port $lport gagal → bore.pub\nRetry dalam 5 detik..." "low" "warning"
    fi
    wait $PID 2>/dev/null || true
    log "[$label] Disconnect. Reconnect 5s..."
    rm -f "/tmp/port_${lport}.txt"
    notify "🔄 Reconnecting [$label]" "Tunnel port $lport terputus. Menghubungkan ulang..." "low" "arrows_counterclockwise"
    sleep 5
  done
}

update_summary() {
  local P22=$(cat /tmp/port_22.txt 2>/dev/null)
  local P80=$(cat /tmp/port_80.txt 2>/dev/null)
  local P443=$(cat /tmp/port_443.txt 2>/dev/null)
  [ -z "$P22" ] && return

  local UPTIME=$(uptime -p 2>/dev/null || echo 'running')
  local BODY="🖥️ Ubuntu 20.04 VPS AKTIF

🔑 SSH  : ssh root@bore.pub -p ${P22}
🔒 Pass : ${ROOT_PASS}
🌐 HTTP : bore.pub:${P80:-pending}
🔐 HTTPS: bore.pub:${P443:-pending}

⏰ Up: $UPTIME"
  notify "✅ VPS ONLINE - Port Ready!" "$BODY" "high" "computer,key,white_check_mark"
}

monitor_loop() {
  local check_interval=300
  while true; do
    sleep $check_interval
    local P22=$(cat /tmp/port_22.txt 2>/dev/null)
    local UPTIME=$(uptime -p 2>/dev/null || echo 'running')
    local MEM=$(free -m 2>/dev/null | awk '/Mem:/{printf "%dMB / %dMB", $3, $2}' || echo 'n/a')
    if [ -n "$P22" ]; then
      notify "📊 VPS Status (5 menit)" "⏰ Uptime: $UPTIME\n💾 RAM: $MEM\n🔑 SSH: bore.pub:$P22" "min" "bar_chart"
    fi
  done
}

# ======================================
log "========================================"
log "  Ubuntu 20.04 VPS | bore tunnel ready"
log "  ntfy topic: $NTFY_TOPIC"
log "========================================"

notify "🚀 VPS Starting..." "Ubuntu 20.04 sedang boot...\nTunnel SSH+HTTP+HTTPS akan aktif sebentar lagi.\nntfy topic: $NTFY_TOPIC" "default" "rocket"

# Pastikan password root sesuai env
echo "root:${ROOT_PASS}" | chpasswd 2>/dev/null || true

# Start SSH daemon
/usr/sbin/sshd && log "SSH daemon started"

# Setup firewall (graceful jika gagal)
setup_firewall

# Placeholder HTTP listener port 80 dan 443
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

# Jalankan 3 bore tunnel secara paralel
bore_tunnel 22  "SSH-22"    &
bore_tunnel 80  "HTTP-80"   &
bore_tunnel 443 "HTTPS-443" &

# Monitor status setiap 5 menit
monitor_loop &

log "Health check port 8080"
exec python3 -c "
import http.server, socketserver
h=http.server.SimpleHTTPRequestHandler
h.log_message=lambda *a:None
socketserver.TCPServer(('',8080),h).serve_forever()
"
