cat << 'EOF' > install_universal_motd.sh
#!/bin/sh
set -eu

# Wajib root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: jalankan sebagai root (sudo)."
  exit 1
fi

echo ">>> Mendeteksi OS dan membersihkan MOTD lama..."

# Hapus file penghalang
rm -f "$HOME/.hushlogin" 2>/dev/null || true

# Untuk Ubuntu/Debian yang punya folder update-motd.d
if [ -d "/etc/update-motd.d" ]; then
  chmod -x /etc/update-motd.d/* 2>/dev/null || true
fi

# Kosongkan file statis /etc/motd
: > /etc/motd

echo ">>> Membuat script dashboard universal..."

cat << 'MOTD' > /etc/profile.d/00-custom-motd.sh
#!/bin/sh

# Tampilkan hanya untuk shell interaktif
case "$-" in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

# --- Warna universal (ANSI) ---
C_RED="$(printf '\033[0;31m')"
C_GREEN="$(printf '\033[0;32m')"
C_BLUE="$(printf '\033[0;34m')"
C_CYAN="$(printf '\033[0;36m')"
C_NC="$(printf '\033[0m')"

# --- Helper: format KB -> MB/GB ---
fmt_kb() {
  awk -v kb="$1" 'BEGIN{
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
    DEF_IFACE="$(ip -o link show up 2>/dev/null | awk -F': ' 'NR==1{print $2; exit}')"
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

# 7. Memory (FIX: akurat di container -> cgroup v2/v1, fallback /proc/meminfo)
MEM_TOTAL_KB=""
MEM_USED_KB=""

# CGroup v2
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  CG_MEM_MAX="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true)"
  CG_MEM_CUR="$(cat /sys/fs/cgroup/memory.current 2>/dev/null || true)"
  if [ -n "$CG_MEM_MAX" ] && [ "$CG_MEM_MAX" != "max" ] 2>/dev/null; then
    MEM_TOTAL_KB=$((CG_MEM_MAX / 1024))
    MEM_USED_KB=$((CG_MEM_CUR / 1024))
  fi
else
  # CGroup v1
  CG_BASE=""
  for d in /sys/fs/cgroup/memory /sys/fs/cgroup; do
    if [ -f "$d/memory.limit_in_bytes" ]; then
      CG_BASE="$d"
      break
    fi
  done

  if [ -n "$CG_BASE" ]; then
    CG_MEM_MAX="$(cat "$CG_BASE/memory.limit_in_bytes" 2>/dev/null || true)"
    CG_MEM_CUR="$(cat "$CG_BASE/memory.usage_in_bytes" 2>/dev/null || true)"

    # Abaikan "unlimited" (angka super besar)
    if [ -n "$CG_MEM_MAX" ] && [ "$CG_MEM_MAX" -gt 0 ] && [ "$CG_MEM_MAX" -lt 9223372036854771712 ] 2>/dev/null; then
      MEM_TOTAL_KB=$((CG_MEM_MAX / 1024))
      MEM_USED_KB=$((CG_MEM_CUR / 1024))
    fi
  fi
fi

# Fallback /proc/meminfo
if [ -z "$MEM_TOTAL_KB" ] || [ -z "$MEM_USED_KB" ] || [ "$MEM_TOTAL_KB" -le 0 ] 2>/dev/null; then
  MEM_TOTAL_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  MEM_AVAIL_KB="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || true)"

  if [ -z "$MEM_AVAIL_KB" ]; then
    MEM_FREE_KB="$(awk '/MemFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_BUF_KB="$(awk '/Buffers:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_CACHE_KB="$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_SRECL_KB="$(awk '/SReclaimable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_SHMEM_KB="$(awk '/Shmem:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    MEM_AVAIL_KB=$((MEM_FREE_KB + MEM_BUF_KB + MEM_CACHE_KB + MEM_SRECL_KB - MEM_SHMEM_KB))
  fi

  MEM_USED_KB=$((MEM_TOTAL_KB - MEM_AVAIL_KB))
fi

MY_MEM="$(fmt_kb "$MEM_USED_KB") / $(fmt_kb "$MEM_TOTAL_KB")"

# 8. Disk Usage (Root /)
MY_DISK="$(df -h / 2>/dev/null | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')"
[ -z "$MY_DISK" ] && MY_DISK="-"

# --- Output ---
printf "\n"
printf "%s=== SYSTEM INFO ===%s\n" "$C_BLUE" "$C_NC"
printf "Hostname  : %s%s%s\n" "$C_CYAN" "$MY_HOST" "$C_NC"
printf "OS Distro : %s\n" "$MY_OS"
printf "Kernel    : %s\n" "$MY_KERNEL"
printf "Uptime    : %s\n" "$MY_UPTIME"
printf "IPv4      : %s%s%s\n" "$C_GREEN" "$MY_IPV4" "$C_NC"
printf "IPv6      : %s%s%s\n" "$C_GREEN" "$MY_IPV6" "$C_NC"
printf "CPU Load  : %s\n" "$MY_LOAD"
printf "Memory    : %s\n" "$MY_MEM"
printf "Disk /    : %s\n" "$MY_DISK"
printf "%s===================%s\n\n" "$C_BLUE" "$C_NC"
MOTD

chmod +x /etc/profile.d/00-custom-motd.sh
echo ">>> Selesai! Logout/login lagi untuk melihat MOTD."

# Hapus installer ini setelah dijalankan
rm -f -- "$0" 2>/dev/null || true
EOF

chmod +x install_universal_motd.sh
./install_universal_motd.sh
