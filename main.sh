cat << 'EOF' > install_universal_motd.sh
#!/bin/sh
set -eu

# Wajib root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: jalankan sebagai root (sudo)."
  exit 1
fi

echo ">>> Cleanup old MOTD configuration..."

# Hapus alias clear dari semua file config yang mungkin
for config_file in /etc/bash.bashrc /etc/bashrc /etc/profile /etc/bash.bash_aliases; do
  if [ -f "$config_file" ]; then
    TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo backup)"
    cp -a "$config_file" "${config_file}.bak-${TS}" 2>/dev/null || true
    sed -i '/alias clear.*show-motd/d' "$config_file" 2>/dev/null || true
    sed -i '/alias clear.*command clear/d' "$config_file" 2>/dev/null || true
    sed -i '/^clear()/,/^}/d' "$config_file" 2>/dev/null || true
    echo "    Cleaned: $config_file"
  fi
done

if [ -f /usr/local/bin/show-motd ]; then
  rm -f /usr/local/bin/show-motd
  echo "    Removed: /usr/local/bin/show-motd"
fi

if [ -f /etc/profile.d/00-custom-motd.sh ]; then
  TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo backup)"
  mv /etc/profile.d/00-custom-motd.sh "/etc/profile.d/00-custom-motd.sh.bak-${TS}" 2>/dev/null || true
  echo "    Backup old: /etc/profile.d/00-custom-motd.sh"
fi

echo ""
echo ">>> Disable & backup MOTD existing..."

for motd_script in /etc/update-motd.d/*; do
  if [ -f "$motd_script" ] && [ -x "$motd_script" ]; then
    chmod -x "$motd_script"
    echo "    Disabled: $motd_script"
  fi
done

for static_motd in /etc/motd /run/motd.dynamic; do
  if [ -f "$static_motd" ]; then
    TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo backup)"
    cp -a "$static_motd" "${static_motd}.bak-${TS}" 2>/dev/null || true
    > "$static_motd"
    echo "    Backup: ${static_motd}.bak-${TS}"
  fi
done

rm -f "$HOME/.hushlogin" 2>/dev/null || true
for user_home in /home/*; do
  if [ -d "$user_home" ]; then
    rm -f "$user_home/.hushlogin" 2>/dev/null || true
  fi
done

echo ""
echo ">>> Install custom MOTD script..."

MOTD_SCRIPT="/usr/local/bin/show-motd"

cat << 'MOTDSCRIPT' > "$MOTD_SCRIPT"
#!/bin/sh
# Script untuk tampilkan MOTD - RAM calculation fix (match htop/free)

# --- Warna universal (ANSI) ---
C_RED="$(printf '\033[0;31m')"
C_GREEN="$(printf '\033[0;32m')"
C_BLUE="$(printf '\033[0;34m')"
C_CYAN="$(printf '\033[0;36m')"
C_YELLOW="$(printf '\033[0;33m')"
C_NC="$(printf '\033[0m')"

# --- Helper: format KB -> MB/GB ---
fmt_kb() {
  awk -v kb="$1" 'BEGIN{
    if (kb <= 0) { print "0MB"; exit }
    mb = kb/1024;
    if (mb >= 1024) printf "%.1fGB", mb/1024;
    else printf "%.0fMB", mb;
  }'
}

# 1. Hostname
MY_HOST="$(hostname 2>/dev/null || echo '-')"

# 2. OS Name
if [ -f /etc/os-release ]; then
  . /etc/os-release
  MY_OS="${PRETTY_NAME:-$(uname -s)}"
else
  MY_OS="$(uname -s 2>/dev/null || echo '-')"
fi

# 3. Kernel
MY_KERNEL="$(uname -r 2>/dev/null || echo '-')"

# 4. Uptime
UP_SECONDS="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)"
UP_MINS=$((UP_SECONDS / 60 % 60))
UP_HOURS=$((UP_SECONDS / 3600 % 24))
UP_DAYS=$((UP_SECONDS / 86400))
MY_UPTIME="${UP_DAYS}d ${UP_HOURS}h ${UP_MINS}m"

# 5. IP Address
MY_IPV4="-"
MY_IPV6="-"
if command -v ip >/dev/null 2>&1; then
  DEF_IFACE="$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')"
  if [ -z "$DEF_IFACE" ]; then
    DEF_IFACE="$(ip -o link show up 2>/dev/null | awk -F': ' '!/lo:/ && !/docker/ && !/veth/ {print $2; exit}')"
  fi

  if [ -n "$DEF_IFACE" ]; then
    MY_IPV4="$(ip -o -4 addr show dev "$DEF_IFACE" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
    [ -z "$MY_IPV4" ] && MY_IPV4="-"

    MY_IPV6="$(ip -o -6 addr show dev "$DEF_IFACE" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
    [ -z "$MY_IPV6" ] && MY_IPV6="-"
  fi
fi

# 6. Load Average
MY_LOAD="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo '-')"

# 7. Memory (FIXED - match htop/free calculation exactly)
# Baca semua nilai dari /proc/meminfo
MEM_TOTAL_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_FREE_KB="$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_AVAILABLE_KB="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_BUFFERS_KB="$(awk '/^Buffers:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_CACHED_KB="$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_SHMEM_KB="$(awk '/^Shmem:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_SRECLAIMABLE_KB="$(awk '/^SReclaimable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"

# Method 1: Jika kernel 3.14+ (ada MemAvailable) - seperti free command
if [ "$MEM_AVAILABLE_KB" -gt 0 ] 2>/dev/null; then
  # Used = Total - Available (method paling akurat untuk kernel modern)
  MEM_USED_KB=$((MEM_TOTAL_KB - MEM_AVAILABLE_KB))
else
  # Method 2: Kernel lama - hitung manual seperti htop
  # Used = Total - Free - Buffers - Cached + Shmem
  # (Shmem sudah termasuk di Cached tapi dipakai, jadi harus ditambah kembali)
  MEM_CACHED_REAL=$((MEM_CACHED_KB + MEM_SRECLAIMABLE_KB - MEM_SHMEM_KB))
  MEM_USED_KB=$((MEM_TOTAL_KB - MEM_FREE_KB - MEM_BUFFERS_KB - MEM_CACHED_REAL))
fi

# Pastikan tidak negatif
if [ "$MEM_USED_KB" -lt 0 ] 2>/dev/null; then
  MEM_USED_KB=0
fi

# Hitung persentase
if [ "$MEM_TOTAL_KB" -gt 0 ] 2>/dev/null; then
  MEM_PCT=$((MEM_USED_KB * 100 / MEM_TOTAL_KB))
  MY_MEM="$(fmt_kb "$MEM_USED_KB") / $(fmt_kb "$MEM_TOTAL_KB") (${MEM_PCT}%)"
  
  # Tambahan info buffer/cache untuk debugging (optional - bisa dihapus)
  MEM_BUFF_CACHE_KB=$((MEM_BUFFERS_KB + MEM_CACHED_KB))
  MY_MEM_DETAIL="$(fmt_kb "$MEM_BUFF_CACHE_KB")"
else
  MY_MEM="-"
  MY_MEM_DETAIL="-"
fi

# 8. Disk Usage
MY_DISK="$(df -h / 2>/dev/null | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')"
[ -z "$MY_DISK" ] && MY_DISK="-"

# 9. Docker Info
DOCKER_INFO=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  DOCKER_RUNNING="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
  DOCKER_TOTAL="$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')"
  DOCKER_INFO="  Docker    : ${C_GREEN}${DOCKER_RUNNING}${C_NC} running / ${DOCKER_TOTAL} total"
fi

# --- Output ---
printf "\n"
printf "%s╔═══════════════════════════════════════╗%s\n" "$C_BLUE" "$C_NC"
printf "%s║        SYSTEM INFORMATION             ║%s\n" "$C_BLUE" "$C_NC"
printf "%s╚═══════════════════════════════════════╝%s\n" "$C_BLUE" "$C_NC"
printf "  Hostname  : %s%s%s\n" "$C_CYAN" "$MY_HOST" "$C_NC"
printf "  OS        : %s\n" "$MY_OS"
printf "  Kernel    : %s\n" "$MY_KERNEL"
printf "  Uptime    : %s\n" "$MY_UPTIME"
printf "  IPv4      : %s%s%s\n" "$C_GREEN" "$MY_IPV4" "$C_NC"
printf "  IPv6      : %s%s%s\n" "$C_GREEN" "$MY_IPV6" "$C_NC"
printf "  CPU Load  : %s\n" "$MY_LOAD"
printf "  Memory    : %s\n" "$MY_MEM"
printf "  Buff/Cache: %s\n" "$MY_MEM_DETAIL"
printf "  Disk /    : %s\n" "$MY_DISK"
if [ -n "$DOCKER_INFO" ]; then
  printf "%s\n" "$DOCKER_INFO"
fi
printf "%s═══════════════════════════════════════%s\n\n" "$C_BLUE" "$C_NC"
MOTDSCRIPT

chmod +x "$MOTD_SCRIPT"

# Profile script untuk auto-load saat login
cat << 'PROFILE' > /etc/profile.d/00-custom-motd.sh
#!/bin/sh
# Auto-show MOTD saat login

case "$-" in
  *i*) 
    if [ -x /usr/local/bin/show-motd ]; then
      /usr/local/bin/show-motd
    fi
    ;;
esac
PROFILE

chmod +x /etc/profile.d/00-custom-motd.sh

# Tambahkan function clear dengan MOTD ke bashrc global
BASHRC_GLOBAL="/etc/bash.bashrc"
if [ ! -f "$BASHRC_GLOBAL" ]; then
  BASHRC_GLOBAL="/etc/bashrc"
fi

if [ -f "$BASHRC_GLOBAL" ]; then
  cat << 'CLEARFUNC' >> "$BASHRC_GLOBAL"

# Custom clear function with MOTD
clear() {
  command clear "$@"
  if [ -x /usr/local/bin/show-motd ]; then
    /usr/local/bin/show-motd
  fi
}
CLEARFUNC
  echo ">>> Function 'clear' ditambahkan ke $BASHRC_GLOBAL"
fi

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   ✓ Custom MOTD Installation Complete!    ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "  ✓ RAM calculation: FIXED (match htop/free)"
echo "  ✓ Old configs cleaned & backed up"
echo "  ✓ MOTD script: /usr/local/bin/show-motd"
echo ""
echo "  Usage:"
echo "    1. Logout/login to see MOTD"
echo "    2. Type 'clear' → MOTD shows"
echo "    3. Manual: 'show-motd'"
echo ""
echo "  Verify RAM accuracy:"
echo "    free -h    (compare with MOTD)"
echo "    htop       (compare with MOTD)"
echo ""

# Self-delete installer
rm -f -- "$0" 2>/dev/null || true
EOF

chmod +x install_universal_motd.sh
./install_universal_motd.sh
