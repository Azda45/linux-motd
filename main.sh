cat << 'EOF' > install_universal_motd.sh
#!/bin/sh
set -eu

# Wajib root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: jalankan sebagai root (sudo)."
  exit 1
fi

echo ">>> Disable & backup MOTD existing..."

# Disable semua MOTD default
for motd_script in /etc/update-motd.d/*; do
  if [ -f "$motd_script" ] && [ -x "$motd_script" ]; then
    chmod -x "$motd_script"
    echo "    Disabled: $motd_script"
  fi
done

# Backup static MOTD files
for static_motd in /etc/motd /run/motd.dynamic; do
  if [ -f "$static_motd" ]; then
    TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo backup)"
    cp -a "$static_motd" "${static_motd}.bak-${TS}"
    > "$static_motd"  # Kosongkan file
    echo "    Backup: ${static_motd}.bak-${TS}"
  fi
done

# Hilangkan hushlogin biar MOTD tampil
rm -f "$HOME/.hushlogin" 2>/dev/null || true

echo ">>> Install custom MOTD..."

TARGET="/etc/profile.d/00-custom-motd.sh"

# Backup kalau sudah ada
if [ -f "$TARGET" ]; then
  TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo backup)"
  BKP="${TARGET}.bak-${TS}"
  cp -a "$TARGET" "$BKP"
  echo ">>> Backup custom MOTD lama: $BKP"
fi

# Tulis MOTD baru (HOST MODE - ignore cgroup Docker)
cat << 'MOTD' > "$TARGET"
#!/bin/sh
# CUSTOM_MOTD_UNIVERSAL v3 (Host mode - accurate RAM for Docker hosts)

# Function untuk tampilkan MOTD
show_motd() {
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
    # shellcheck disable=SC1091
    . /etc/os-release
    MY_OS="${PRETTY_NAME:-$(uname -s)}"
  else
    MY_OS="$(uname -s 2>/dev/null || echo '-')"
  fi

  # 3. Kernel
  MY_KERNEL="$(uname -r 2>/dev/null || echo '-')"

  # 4. Uptime (manual)
  UP_SECONDS="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)"
  UP_MINS=$((UP_SECONDS / 60 % 60))
  UP_HOURS=$((UP_SECONDS / 3600 % 24))
  UP_DAYS=$((UP_SECONDS / 86400))
  MY_UPTIME="${UP_DAYS}d ${UP_HOURS}h ${UP_MINS}m"

  # 5. IP Address (pakai iproute2 kalau ada)
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

  # 7. Memory (HOST MODE - langsung dari /proc/meminfo, IGNORE cgroup)
  MEM_TOTAL_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  MEM_AVAIL_KB="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || true)"

  if [ -z "$MEM_AVAIL_KB" ] || [ "$MEM_AVAIL_KB" = "0" ]; then
    MEM_FREE_KB="$(awk '/MemFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_BUF_KB="$(awk '/Buffers:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_CACHE_KB="$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_SRECL_KB="$(awk '/SReclaimable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_SHMEM_KB="$(awk '/Shmem:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_AVAIL_KB=$((MEM_FREE_KB + MEM_BUF_KB + MEM_CACHE_KB + MEM_SRECL_KB - MEM_SHMEM_KB))
  fi

  MEM_USED_KB=$((MEM_TOTAL_KB - MEM_AVAIL_KB))

  if [ "$MEM_TOTAL_KB" -gt 0 ] 2>/dev/null; then
    MEM_PCT=$((MEM_USED_KB * 100 / MEM_TOTAL_KB))
    MY_MEM="$(fmt_kb "$MEM_USED_KB") / $(fmt_kb "$MEM_TOTAL_KB") (${MEM_PCT}%)"
  else
    MY_MEM="-"
  fi

  # 8. Disk Usage (Root /)
  MY_DISK="$(df -h / 2>/dev/null | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')"
  [ -z "$MY_DISK" ] && MY_DISK="-"

  # 9. Docker Info (opsional - hanya jika docker aktif)
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
  printf "  Disk /    : %s\n" "$MY_DISK"
  if [ -n "$DOCKER_INFO" ]; then
    printf "%s\n" "$DOCKER_INFO"
  fi
  printf "%s═══════════════════════════════════════%s\n\n" "$C_BLUE" "$C_NC"
}

# Tampilkan MOTD hanya untuk shell interaktif saat login
case "$-" in
  *i*) 
    # Cek apakah ini login shell (bukan setelah clear)
    if [ -z "${MOTD_SHOWN:-}" ]; then
      show_motd
      export MOTD_SHOWN=1
    fi
    ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

# Alias clear untuk tampilkan MOTD lagi
alias clear='command clear && show_motd'
MOTD

chmod +x "$TARGET"

echo ""
echo ">>> ✓ Custom MOTD berhasil di-install!"
echo ">>> ✓ MOTD lama sudah di-disable & di-backup"
echo ">>> ✓ RAM calculation: HOST mode (physical memory)"
echo ">>> ✓ MOTD akan muncul lagi setiap kali 'clear'"
echo ">>> Logout/login untuk melihat MOTD baru."
echo ""

# Self-delete installer
rm -f -- "$0" 2>/dev/null || true
EOF

chmod +x install_universal_motd.sh
./install_universal_motd.sh
