#!/bin/bash
# ==================================================
# TCP/UDP 网络调优脚本（精简诚实版）
# - 去掉所有表演性假进度条与凭空打印的"指标"
# - 删除内核里根本不存在的伪参数 tcp_congestion_control_version
# - tcp_ecn 改为更安全的 2，移除会缩短重传的 tcp_retries2
# - 不再从 http 远程下载并以 root 执行（消除中间人风险）
# 用法：sudo bash tcp_tune_clean.sh
# ==================================================

set -u

if [ "$EUID" -ne 0 ]; then
    echo "错误: 必须使用 root 权限运行（sudo bash $0）" >&2
    exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; PURPLE='\033[0;35m'; NC='\033[0m'

SYSCTL_OPT="/etc/sysctl.d/99-network-performance.conf"
BBR_OPT="/etc/sysctl.d/10-bbr.conf"
LIMITS_OPT="/etc/security/limits.d/99-network-performance.conf"

draw_line() { echo -e "${YELLOW}--------------------------------------------------${NC}"; }

# 过滤掉回环/容器/隧道等虚拟接口，只对物理网卡操作
phys_interfaces() {
    ls /sys/class/net | grep -vE '^(lo|docker|veth|br-|tun|tap|wg|sit|any)'
}

# --------------------------------------------------
# 0. 一键体检（动手前先看该不该调 + 有没有抢资源的进程）
# --------------------------------------------------
health_check() {
    echo -e "\n${YELLOW}========== 一键体检报告 ==========${NC}"

    # 系统 / 资源
    local os kern cpu memmb
    os=$(grep -oP '(?<=^PRETTY_NAME=").*(?=")' /etc/os-release 2>/dev/null)
    kern=$(uname -r); cpu=$(nproc); memmb=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 ))
    echo -e "  系统: ${CYAN}${os}${NC} | 内核: ${CYAN}${kern}${NC} | ${CYAN}${cpu}${NC}核 / ${CYAN}${memmb}MB${NC}"

    # BBR
    local cc qd avail
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    avail=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
    if [ "$cc" = "bbr" ]; then
        echo -e "  拥塞算法: ${GREEN}${cc} + ${qd}${NC}  ${GREEN}(已最优,无需动)${NC}"
    elif echo "$avail" | grep -qw bbr; then
        echo -e "  拥塞算法: ${RED}${cc}${NC}  ${YELLOW}(内核支持 bbr,建议选 2 开启)${NC}"
    else
        echo -e "  拥塞算法: ${RED}${cc}${NC}  ${RED}(内核不支持 bbr,需升级内核)${NC}"
    fi

    # 缓冲区是否已调
    local rmax
    rmax=$(sysctl -n net.core.rmem_max 2>/dev/null)
    if [ "${rmax:-0}" -ge $((16*1024*1024)) ]; then
        echo -e "  读缓冲 rmem_max: ${GREEN}$((rmax/1024/1024))MB (已是大缓冲,提速大头已在)${NC}"
    else
        echo -e "  读缓冲 rmem_max: ${RED}$((rmax/1024))KB (偏小,建议选 3 调优)${NC}"
    fi

    # 网卡物理天花板
    local eth ringmax
    eth=$(phys_interfaces | head -1)
    if [ -n "$eth" ] && command -v ethtool &>/dev/null; then
        ringmax=$(ethtool -g "$eth" 2>/dev/null | awk '/Pre-set maximums/{f=1} f&&/RX:/{print $2; exit}')
        echo -e "  网卡 ${eth} RX-ring 上限: ${CYAN}${ringmax:-未知}${NC} ${YELLOW}(过小是NAT小鸡物理天花板,软件无解)${NC}"
    fi

    # 代理检测
    echo -e "  ${YELLOW}--- 代理进程 ---${NC}"
    local ssout proxy
    ssout=$(ss -tulnp 2>/dev/null)
    # 只抽进程名并去重，不打印每个 fd
    proxy=$(echo "$ssout" | grep -oiE '"(xray|sing-box|sui|hysteria|trojan|ss-server|tuic|naive)"' | tr -d '"' | sort -u | tr '\n' ' ')
    if [ -n "$proxy" ]; then
        echo -e "  ${GREEN}检测到:${NC} ${proxy}"
        if echo "$ssout" | grep -iE '^udp' | grep -qiE 'sui|sing-box|hysteria|tuic|xray'; then
            echo -e "  ${CYAN}走 UDP(QUIC/Hysteria2),UDP 缓冲调优有用${NC}"
        fi
    else
        echo -e "  ${YELLOW}未识别到常见代理(可能名称特殊,手动 ss -tulnp 看)${NC}"
    fi

    # 抢资源的可疑进程
    echo -e "  ${YELLOW}--- CPU 占用 Top5 (留意陌生进程) ---${NC}"
    ps -eo pcpu,pid,user,comm --sort=-pcpu 2>/dev/null | head -6 | sed 's/^/  /'
    echo -e "  ${YELLOW}--- 可疑自启服务(已排除系统常见项) ---${NC}"
    systemctl list-unit-files --state=enabled 2>/dev/null \
        | awk '{print $1}' | grep -vE 'ssh|cron|systemd|network|getty|dbus|rsyslog|chrony|multipath|e2scrub|fstrim|apport|unattended|motd|\.target|^UNIT' \
        | sed 's/^/  /' | head -10
    echo -e "  ${PURPLE}ℹ 发现陌生服务(尤其带 download/挖矿/dht/bt 特征)→ 多半在抢带宽,可考虑停掉${NC}"

    echo -e "${YELLOW}==================================${NC}"
}

# --------------------------------------------------
# 1. IPv4 优先解析（解决 IPv6 绕路导致的握手卡顿）
# --------------------------------------------------
set_ipv4_priority() {
    echo -e "\n${YELLOW}>>> 设置 IPv4 优先解析...${NC}"
    [ -f /etc/gai.conf ] && [ ! -f /etc/gai.conf.bak ] && cp /etc/gai.conf /etc/gai.conf.bak
    # 去掉旧的同名行后再追加，避免重复
    sed -i '\#^precedence ::ffff:0:0/96#d' /etc/gai.conf 2>/dev/null || touch /etc/gai.conf
    echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
    echo -e "${GREEN}✅ 已设置为 IPv4 优先。${NC}"
}

# --------------------------------------------------
# 2. BBR + FQ 拥塞算法
# --------------------------------------------------
enable_bbr() {
    echo -e "\n${YELLOW}>>> 启用 BBR + FQ...${NC}"
    cat > "$BBR_OPT" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl --system &>/dev/null
    local cc qd
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    if [ "$cc" = "bbr" ]; then
        echo -e "${GREEN}✅ 拥塞算法: ${cc} | 队列: ${qd}${NC}"
    else
        echo -e "${RED}⚠ 当前算法为 ${cc}，内核可能未编译 BBR（需 4.9+ 且启用 tcp_bbr 模块）。${NC}"
    fi
}

# --------------------------------------------------
# 3. 内核缓冲区与连接调优
# --------------------------------------------------
tune_sysctl() {
    echo -e "\n${YELLOW}>>> 部署内核调优配置...${NC}"
    local mem_total_kb cpu_count buf_bytes
    mem_total_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    cpu_count=$(nproc)
    # 缓冲区 = 内存的 5%，但封顶 64MB，避免大内存机器把每条配置撑得过大
    buf_bytes=$(( mem_total_kb * 5 / 100 * 1024 ))
    [ "$buf_bytes" -gt $((64*1024*1024)) ] && buf_bytes=$((64*1024*1024))

    echo -e "  核心数: ${CYAN}${cpu_count}${NC} | 内存: ${CYAN}$((mem_total_kb/1024))MB${NC} | 缓冲区上限: ${CYAN}$((buf_bytes/1024/1024))MB${NC}"

    cat > "$SYSCTL_OPT" <<EOF
# --- 队列与拥塞算法 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 缓冲区（高带宽长延迟链路提速的关键）---
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = ${buf_bytes}
net.core.wmem_max = ${buf_bytes}
net.ipv4.tcp_rmem = 4096 87380 ${buf_bytes}
net.ipv4.tcp_wmem = 4096 65536 ${buf_bytes}
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# --- 代理/Reality 针对性 ---
net.ipv4.tcp_notsent_lowat = 16384   # 降低本地发送积压，改善 TTFB
net.ipv4.tcp_mtu_probing = 1         # 防运营商阻断 ICMP 造成的 MTU 黑洞
net.ipv4.udp_rmem_min = 16384        # QUIC/Hysteria2 高并发缓冲
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_max_orphans = 32768

# --- ECN：用 2（被动接受，不主动发起），比 1 更不容易被中间设备打断 ---
net.ipv4.tcp_ecn = 2

# --- 连接稳定性 ---
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
# 注: 原脚本的 tcp_retries2=8 会让丢包时更快断连，已移除，保留内核默认(15)
# 注: 原脚本的 tcp_congestion_control_version=3 是不存在的伪参数，已删除
EOF

    sysctl --system &>/dev/null

    mkdir -p /etc/security/limits.d/
    cat > "$LIMITS_OPT" <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
EOF

    if command -v iptables &>/dev/null; then
        iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
            && echo -e "${GREEN}  ✔ 已部署 MSS Clamp 规则${NC}"
    fi

    echo -e "${GREEN}✅ 内核调优完成，配置已持久化至 ${SYSCTL_OPT}（重启仍生效）。${NC}"
}

# --------------------------------------------------
# 4. 网卡多队列 / RPS（消除单核软中断瓶颈）
# --------------------------------------------------
optimize_nic() {
    echo -e "\n${YELLOW}>>> 配置网卡 RPS 多核分发...${NC}"
    if ! command -v ethtool &>/dev/null; then
        (apt-get update -qq && apt-get install -y -qq ethtool) 2>/dev/null \
            || yum install -y -q ethtool 2>/dev/null || true
    fi
    local cpu_count rps_cpus eth max_rx
    cpu_count=$(nproc)
    rps_cpus=$(printf '%x' $(( (1 << cpu_count) - 1 )))
    for eth in $(phys_interfaces); do
        max_rx=$(ethtool -g "$eth" 2>/dev/null | awk '/Pre-set maximums/{f=1} f&&/RX:/{print $2; exit}')
        ethtool -G "$eth" rx "${max_rx:-1024}" tx "${max_rx:-1024}" &>/dev/null || true
        for f in /sys/class/net/$eth/queues/rx-*/rps_cpus; do [ -f "$f" ] && echo "$rps_cpus" > "$f"; done
        for f in /sys/class/net/$eth/queues/rx-*/rps_flow_cnt; do [ -f "$f" ] && echo 4096 > "$f"; done
        echo -e "  ${GREEN}✔${NC} $eth -> RPS mask 0x${rps_cpus}"
    done
    sysctl -w net.core.rps_sock_flow_entries=32768 &>/dev/null
    echo -e "${GREEN}✅ 网卡软中断已平摊至 ${cpu_count} 核。${NC}"
    echo -e "${YELLOW}ℹ 注: RPS 仅在 /sys 内存中生效，重启后失效；如需开机自启请配 systemd/rc.local。${NC}"
}

# --------------------------------------------------
# 5. 回退所有更改
# --------------------------------------------------
rollback() {
    echo -e "\n${YELLOW}>>> 回退所有调优...${NC}"
    rm -f "$SYSCTL_OPT" "$LIMITS_OPT" "$BBR_OPT"

    if [ -f /etc/gai.conf.bak ]; then
        mv -f /etc/gai.conf.bak /etc/gai.conf
    else
        sed -i '\#^precedence ::ffff:0:0/96#d' /etc/gai.conf 2>/dev/null || true
    fi

    sysctl -w net.ipv4.tcp_congestion_control=cubic &>/dev/null || true
    sysctl -w net.core.default_qdisc=pfifo_fast &>/dev/null || true
    sysctl -w net.core.rps_sock_flow_entries=0 &>/dev/null || true

    command -v iptables &>/dev/null && \
        iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true

    local eth f
    for eth in $(phys_interfaces); do
        for f in /sys/class/net/$eth/queues/rx-*/rps_cpus; do [ -f "$f" ] && echo 0 > "$f"; done
    done

    sysctl --system &>/dev/null
    echo -e "${GREEN}✅ 已回退，所有独立配置文件已清理，内存参数恢复默认。${NC}"
}

# --------------------------------------------------
# 主菜单
# --------------------------------------------------
status() {
    local v="$1" want="$2"
    [ "$v" = "$want" ] && echo -e "${GREEN}[已激活]${NC}" || echo -e "${RED}[未开启]${NC}"
}

while true; do
    s_bbr=$(status "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" bbr)
    [ -f "$SYSCTL_OPT" ] && s_sysctl="${GREEN}[已激活]${NC}" || s_sysctl="${RED}[未开启]${NC}"
    s_nic=$(status "$(sysctl -n net.core.rps_sock_flow_entries 2>/dev/null)" 32768)
    grep -q "^precedence ::ffff:0:0/96" /etc/gai.conf 2>/dev/null \
        && s_ipv4="${GREEN}[已激活]${NC}" || s_ipv4="${RED}[未开启]${NC}"

    clear
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "${YELLOW}        TCP/UDP 网络调优（精简诚实版）${NC}"
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "  9. 一键体检（先看该不该调 + 有无抢资源进程）"
    echo -e "  1. IPv4 优先解析   -> $s_ipv4"
    echo -e "  2. BBR + FQ        -> $s_bbr"
    echo -e "  3. 内核缓冲区调优  -> $s_sysctl"
    echo -e "  4. 网卡 RPS 多核   -> $s_nic"
    echo -e "  5. 一键回退默认"
    echo -e "  0. 退出"
    draw_line
    echo -e "当前: 算法 ${GREEN}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)${NC} | 句柄 ${GREEN}$(ulimit -n)${NC}"
    draw_line
    read -p "请选择 [0-9]: " opt
    case "$opt" in
        9) health_check ;;
        1) set_ipv4_priority ;;
        2) enable_bbr ;;
        3) tune_sysctl ;;
        4) optimize_nic ;;
        5) rollback ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误${NC}" ;;
    esac
    read -p "按回车返回..."
done
