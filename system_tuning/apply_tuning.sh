#!/usr/bin/env bash
# ==============================================================================
# apply_tuning.sh - Install & Apply 8GB RAM + ZRAM Tuning for Pi 5
# Omarchy Quattro Pi 5 Agent Swarm
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo " Omarchy Quattro Pi 5: Applying 8GB RAM & NVMe System Tuning"
echo "=================================================================="

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (sudo $0)" >&2
    exit 1
fi

# Step 1: Install zram-generator configuration
echo "[1/3] Installing zram-generator configuration..."
mkdir -p /etc/systemd
install -m 0644 "${SCRIPT_DIR}/zram-generator.conf" "/etc/systemd/zram-generator.conf"

# Step 2: Install kernel sysctl parameters
echo "[2/3] Installing sysctl tuning (/etc/sysctl.d/99-pi5-sysctl.conf)..."
mkdir -p /etc/sysctl.d
install -m 0644 "${SCRIPT_DIR}/99-pi5-sysctl.conf" "/etc/sysctl.d/99-pi5-sysctl.conf"

# Step 3: Apply sysctl configuration immediately
echo "[3/3] Applying sysctl parameters..."

# Detect installed RAM and dynamically scale vm.dirty_background_bytes.
# 16 GB Pi 5: 400 MB dirty writeback buffer avoids premature flush stalls.
# 8 GB Pi 5:  200 MB dirty writeback buffer.
# 4 GB Pi 5:  100 MB dirty writeback buffer prevents write queue runaway.
TOTAL_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "0")
if [ "${TOTAL_RAM_MB}" -gt 12000 ]; then
    echo "      Detected ${TOTAL_RAM_MB} MB RAM (16GB SKU) — scaling vm.dirty_background_bytes to 400MB."
    sed -i -E 's/^vm\.dirty_background_bytes=.*/vm.dirty_background_bytes=419430400/' /etc/sysctl.d/99-pi5-sysctl.conf
elif [ "${TOTAL_RAM_MB}" -gt 6000 ]; then
    echo "      Detected ${TOTAL_RAM_MB} MB RAM (8GB SKU) — setting vm.dirty_background_bytes to 200MB."
    sed -i -E 's/^vm\.dirty_background_bytes=.*/vm.dirty_background_bytes=209715200/' /etc/sysctl.d/99-pi5-sysctl.conf
elif [ "${TOTAL_RAM_MB}" -gt 0 ]; then
    echo "      Detected ${TOTAL_RAM_MB} MB RAM (<=4GB SKU) — setting vm.dirty_background_bytes to 100MB."
    sed -i -E 's/^vm\.dirty_background_bytes=.*/vm.dirty_background_bytes=104857600/' /etc/sysctl.d/99-pi5-sysctl.conf
else
    echo "      [WARN] Could not read /proc/meminfo; RAM size unknown — leaving default 200MB."
fi

sysctl -p /etc/sysctl.d/99-pi5-sysctl.conf

# Reload systemd generator if running
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    echo "      Reloading systemd daemon..."
    systemctl daemon-reload
    if systemctl is-enabled systemd-zram-setup@zram0.service >/dev/null 2>&1; then
        systemctl restart systemd-zram-setup@zram0.service || true
    fi
fi

echo "=================================================================="
echo " System tuning successfully applied:"
echo "   - ZRAM: dynamic swap device (min(ram/2, 8GB)) with zstd compression"
echo "   - vm.swappiness = 100"
echo "   - vm.vfs_cache_pressure = 50"
echo "   - vm.dirty_background_bytes = 209715200 (200MB)"
echo "   - vm.dirty_ratio = 10"
echo "=================================================================="
