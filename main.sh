cat << 'EOF' > install_universal_motd.sh
#!/bin/sh

# --- 1. BERSIH-BERSIH (CLEANUP) ---
echo ">>> Mendeteksi OS dan membersihkan MOTD lama..."

# Hapus file penghalang
rm -f ~/.hushlogin

# Untuk Ubuntu/Debian yang punya folder update-motd.d
if [ -d "/etc/update-motd.d" ]; then
    chmod -x /etc/update-motd.d/* 2>/dev/null
fi

# Kosongkan file statis /etc/motd (Debian/Alpine sering pakai ini)
> /etc/motd

# --- 2. BUAT SCRIPT TAMPILAN (POSIX COMPLIANT) ---
echo ">>> Membuat script dashboard universal..."

cat << 'MOTD' > /etc/profile.d/00-custom-motd.sh
#!/bin/sh

# --- Warna Universal ---
# Menggunakan kode ANSI standar biar jalan di bash, sh, dash, ash
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_NC='\033[0m'

# --- Deteksi Data (Kompatibel Alpine/Busybox & Ubuntu/Gnu) ---

# 1. Hostname
MY_HOST=$(hostname)

# 2. OS Name (Ambil dari /etc/os-release biar akurat di semua distro)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    MY_OS="$PRETTY_NAME"
else
    MY_OS=$(uname -s)
fi

# 3. Kernel
MY_KERNEL=$(uname -r)

# 4. Uptime (Manual Math karena 'uptime -p' gak ada di Alpine)
UP_SECONDS="$(cat /proc/uptime | grep -o '^[0-9]\+')"
UP_MINS=$((UP_SECONDS / 60 % 60))
UP_HOURS=$((UP_SECONDS / 3600 % 24))
UP_DAYS=$((UP_SECONDS / 86400))
MY_UPTIME="${UP_DAYS}d ${UP_HOURS}h ${UP_MINS}m"

# 5. IP Address (Cara paling universal parsing route)
# Cari interface yang punya default route
DEF_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$DEF_IFACE" ]; then
    # Fallback kalau gak ada internet, ambil interface pertama yang UP
    DEF_IFACE=$(ip link | grep 'state UP' | awk -F: '{print $2}' | head -n1 | tr -d ' ')
fi

# Ambil IP (Filter scope global biar gak dapet localhost/link-local)
MY_IPV4=$(ip -4 addr show "$DEF_IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
MY_IPV6=$(ip -6 addr show "$DEF_IFACE" | grep scope | grep -v "link" | grep -oP '(?<=inet6\s)[\da-f:]+' | head -n1)
[ -z "$MY_IPV6" ] && MY_IPV6="-"

# 6. Load Average
MY_LOAD=$(cat /proc/loadavg | awk '{print $1}')

# 7. Memory (Parsing /proc/meminfo biar aman untuk Alpine & Ubuntu)
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_AVAIL_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
# Kalau MemAvailable gak ada (kernel lama/alpine tertentu), hitung manual dari Free+Buffers+Cached
if [ -z "$MEM_AVAIL_KB" ]; then
    MEM_FREE_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
    MEM_BUF_KB=$(grep Buffers /proc/meminfo | awk '{print $2}')
    MEM_CACHE_KB=$(grep ^Cached /proc/meminfo | awk '{print $2}')
    MEM_AVAIL_KB=$((MEM_FREE_KB + MEM_BUF_KB + MEM_CACHE_KB))
fi
MEM_USED_KB=$((MEM_TOTAL_KB - MEM_AVAIL_KB))
# Konversi ke MB
MY_MEM="$((MEM_USED_KB / 1024))MB / $((MEM_TOTAL_KB / 1024))MB"

# 8. Disk Usage (Root /)
MY_DISK=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')

# --- TAMPILAN OUTPUT ---
echo ""
echo -e "${C_BLUE}=== SYSTEM INFO ===${C_NC}"
echo -e "Hostname  : ${C_CYAN}$MY_HOST${C_NC}"
echo -e "OS Distro : $MY_OS"
echo -e "Kernel    : $MY_KERNEL"
echo -e "Uptime    : $MY_UPTIME"
echo -e "IPv4      : ${C_GREEN}$MY_IPV4${C_NC}"
echo -e "IPv6      : ${C_GREEN}$MY_IPV6${C_NC}"
echo -e "CPU Load  : $MY_LOAD"
echo -e "Memory    : $MY_MEM"
echo -e "Disk /    : $MY_DISK"
echo -e "${C_BLUE}===================${C_NC}"
echo ""
MOTD

# --- 3. FINALISASI ---
chmod +x /etc/profile.d/00-custom-motd.sh
echo ">>> Selesai! Silakan logout dan login kembali untuk melihat hasilnya."

EOF

# Jalankan installer langsung
sh install_universal_motd.sh
