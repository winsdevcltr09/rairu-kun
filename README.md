# FREE VPS via Cloudflare Tunnel

### Spesifikasi
1. 7 GB RAM 💽
2. 1.2 TB Storage 💾
3. Up to 100Gbps 🚀
4. 69 Core CPU 🚥
5. Google Cloud Technology 🌐

---

## Tutorial Deploy di Railway 🇮🇩

### 1. Siapkan Cloudflare Tunnel Token

1. Login ke [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Buka **Networks → Tunnels → Create a Tunnel**
3. Pilih **Cloudflared**, beri nama tunnel (contoh: `rairu-vps`)
4. Salin **Tunnel Token** yang diberikan
5. Di bagian **Public Hostname**, tambahkan:
   - **SSH**: `ssh.methatech.eu.org` → Service: `ssh://localhost:22`
   - **HTTP**: `methatech.eu.org` → Service: `http://localhost:80`

### 2. Deploy ke Railway

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new/template/BzFWCH?referralCode=dG01iI)

Isi environment variable berikut di Railway:

| Variable | Nilai |
|---|---|
| `CLOUDFLARE_TUNNEL_TOKEN` | Token dari Cloudflare dashboard |
| `ROOT_PASS` | Password SSH yang kamu mau |
| `NTFY_TOPIC` | Topic ntfy.sh untuk notifikasi |

### 3. Cara Konek SSH

Install `cloudflared` di komputer kamu:
```bash
# Linux/macOS
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
```

Tambahkan ke `~/.ssh/config`:
```
Host ssh.methatech.eu.org
    ProxyCommand cloudflared access ssh --hostname %h
    User root
```

Lalu SSH:
```bash
ssh root@ssh.methatech.eu.org
```

### 4. Notifikasi Otomatis

Setelah VPS online, kamu akan dapat notifikasi di ntfy.sh dengan instruksi lengkap cara konek.

---

## Keunggulan vs bore tunnel

| Fitur | bore.pub | Cloudflare Tunnel |
|---|---|---|
| Domain | Random port `bore.pub:XXXXX` | Domain tetap `ssh.methatech.eu.org` |
| Stabilitas | Sering putus | Sangat stabil (Cloudflare infra) |
| Keamanan | Port publik terbuka | Terenkripsi via Cloudflare |
| Railway limit | Port terbuka bisa kena limit | Hanya 1 port (8080 healthcheck) |

---

## Support Penulis ☕
paypal: https://paypal.me/dedeklender
