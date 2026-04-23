#!/bin/bash
# TCP 网络优化脚本 - 适用于代理服务器 (Ubuntu/Debian)
# 用法: bash optimize-tcp.sh

set -e

echo "=== TCP 网络优化脚本 ==="

# 检查是否root
if [ "$EUID" -ne 0 ]; then
    echo "请用 root 运行: sudo bash optimize-tcp.sh"
    exit 1
fi

# 获取内存大小(KB)，计算tcp_mem参数
MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_PAGES=$((MEM_KB / 4))
TCP_MEM_MIN=$((MEM_PAGES / 32))
TCP_MEM_PRESSURE=$((MEM_PAGES / 16))
TCP_MEM_MAX=$((MEM_PAGES / 4))

echo "内存: $((MEM_KB / 1024)) MB，tcp_mem: $TCP_MEM_MIN $TCP_MEM_PRESSURE $TCP_MEM_MAX"

# 写入配置（幂等，先删除旧的再写）
SYSCTL_CONF=/etc/sysctl.conf
sed -i '/# === TCP优化/,/tcp_mtu_probing/d' "$SYSCTL_CONF" 2>/dev/null || true

cat >> "$SYSCTL_CONF" << EOF

# === TCP优化 ($(date +%Y-%m-%d)) ===
# BBR拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
# 接收/发送缓冲区 64MB
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
# 禁用空闲后慢启动（视频流防卡顿最关键）
net.ipv4.tcp_slow_start_after_idle = 0
# TCP Fast Open 双向启用
net.ipv4.tcp_fastopen = 3
# 增大队列
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
# TCP内存（根据实际内存自动计算）
net.ipv4.tcp_mem = $TCP_MEM_MIN $TCP_MEM_PRESSURE $TCP_MEM_MAX
# 加快连接回收
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
# MTU自动探测（跨国高丢包环境有帮助）
net.ipv4.tcp_mtu_probing = 1
EOF

# 立即生效
sysctl -p

echo ""
echo "=== 验证关键参数 ==="
sysctl net.ipv4.tcp_congestion_control \
       net.ipv4.tcp_slow_start_after_idle \
       net.ipv4.tcp_fastopen \
       net.ipv4.tcp_mtu_probing

echo ""
echo "✓ 优化完成，重启后自动生效"
