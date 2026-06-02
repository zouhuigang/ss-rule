# VPS 翻墙 / 代理 调优手册

> 适用：Linux VPS（Ubuntu/Debian 为主），跑 sing-box / xray / s-ui / hysteria 等代理。
> 核心理念：**先体检，再下手**。大多数提速来自 BBR + 大缓冲区，以及干掉抢资源的进程，而不是堆一堆花哨参数。
> 配套脚本：`tcp_tune_clean.sh`（菜单式，含一键回退）。

---

## 0. 一句话结论（先有预期再动手）

- **真正提速的大头只有两样**：① BBR + FQ 拥塞算法；② 足够大的 TCP 读写缓冲区（高带宽长延迟链路才吃得满）。这两样到位，速度就上来了。
- 网上脚本里大量"内核注入 / 深度加载 / BBR3 引擎"之类的进度条和指标，**绝大多数是表演**，不产生任何实际效果。
- **别迷信调参**。很多时候机器早就调好了，瓶颈是别的进程在抢带宽，或是 NAT 小鸡的物理天花板（网卡单队列、ring 太小）。

---

## 1. 上机体检（动手前必做）

```bash
# 系统 / 内核 / 资源
cat /etc/os-release | grep PRETTY_NAME
uname -r
nproc; grep MemTotal /proc/meminfo

# 拥塞算法现状（很多新内核默认就是 bbr+fq）
sysctl -n net.ipv4.tcp_congestion_control
sysctl -n net.core.default_qdisc
sysctl -n net.ipv4.tcp_available_congestion_control   # 看 bbr 是否可用

# 现有缓冲区（看是否已经被调过）
sysctl -n net.core.rmem_max net.core.wmem_max
sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem

# 已有的调优配置从哪来
grep -vE '^\s*#|^\s*$' /etc/sysctl.conf
ls -la /etc/sysctl.d/

# 网卡能力（ring 上限往往是物理天花板）
ethtool -g $(ls /sys/class/net | grep -vE '^(lo|docker|veth|br-|tun|tap|wg)' | head -1)
```

**判断要点**
- 若 `tcp_congestion_control` 已是 `bbr`、`rmem_max` 已是几十 MB → 机器已被调过，**别重复折腾**，直接跳到第 4 步（找抢资源的进程）。
- 若 `available_congestion_control` 里没有 `bbr` → 内核太老，需先升级内核（4.9+），否则 BBR 开不了。
- `ethtool -g` 的 `Pre-set maximums` 很小（如 256）→ 这是 NAT 小鸡的物理上限，软件层无法突破。

---

## 2. 找出真正在跑的代理（决定要不要调 UDP）

```bash
# 看监听端口和进程
ss -tulnp | grep -vE '127.0.0.1|::1'
ps aux | grep -iE 'xray|sing-box|s-ui|sui|hysteria|trojan|shadowsocks|tuic|naive' | grep -v grep
```

- 看到代理在 **UDP** 端口（如 UDP/443）监听 → 走的是 **QUIC / Hysteria2 / TUIC**，**UDP 缓冲区调优有用**。
- 只有 TCP → UDP 那几项可以不加，但加了也无害。
- 记下代理进程 PID，下一步查它的文件句柄上限。

---

## 3. 应用调优（只补缺的，别覆盖已有的）

> 原则：用独立 drop-in 文件，**不要去改 `/etc/sysctl.conf` 里别人已经写好的项**，避免冲突和重复。

### 3.1 BBR + FQ（若还没开）

```bash
cat > /etc/sysctl.d/10-bbr.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl --system
# 验证
sysctl -n net.ipv4.tcp_congestion_control   # 应输出 bbr
```

### 3.2 缓冲区与连接调优（若还没调过大缓冲）

```bash
# 缓冲区取内存的 5%，但封顶 64MB，避免大内存机把参数撑过头
MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
BUF=$(( MEM_KB * 5 / 100 * 1024 ))
[ "$BUF" -gt $((64*1024*1024)) ] && BUF=$((64*1024*1024))

cat > /etc/sysctl.d/99-network-performance.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 缓冲区（提速关键）
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = ${BUF}
net.core.wmem_max = ${BUF}
net.ipv4.tcp_rmem = 4096 87380 ${BUF}
net.ipv4.tcp_wmem = 4096 65536 ${BUF}
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# 代理针对性
net.ipv4.tcp_notsent_lowat = 16384   # 降低本地发送积压，改善网页首包延迟(TTFB)
net.ipv4.tcp_mtu_probing = 1         # 防运营商阻断 ICMP 造成 MTU 黑洞
net.ipv4.udp_rmem_min = 16384        # QUIC/Hysteria2 用得上
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_ecn = 2                 # 被动接受，比 1 更不易被中间设备打断

# 稳定性
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
EOF
sysctl --system
```

### 3.3 文件句柄上限（连接数多的代理需要）

```bash
# 先看代理进程当前上限（替换 PID）
cat /proc/<PID>/limits | grep 'open files'

# 若上限是 1024 这种小值，提高它：
cat > /etc/security/limits.d/99-network-performance.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
EOF
```

> 注意：`limits.d` 对 **systemd 服务不生效**。若代理是 systemd 服务，要在 service 文件里加 `LimitNOFILE=1048576` 再 `systemctl daemon-reload && systemctl restart <服务>`。
> （像 s-ui 这类面板装的代理，默认往往已经是 52 万+，不用动。先查再说。）

### 3.4 MSS 钳制（可选，防跨境 MTU 超时）

```bash
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

---

## 4. ⭐ 比调参更重要：干掉抢资源的进程

> **实战经验**：很多"翻墙慢"根本不是 TCP 没调好，而是机器上有别的进程在抢带宽 / CPU / 网卡。
> 典型元凶：BT/DHT 爬虫、挖矿、被植入的后门、跑满的备份/同步任务。

```bash
# 看谁在吃 CPU / 流量
top -b -n1 | head -20
ss -tunp | awk '{print $NF}' | sort | uniq -c | sort -rn | head   # 连接数 top
ps aux --sort=-%cpu | head -10

# 看可疑自启服务
systemctl list-units --type=service --state=running
systemctl list-unit-files --state=enabled | grep -vE 'ssh|cron|systemd|network|getty|dbus'
```

**判断**：发现陌生进程（尤其以独立用户运行、对外大量 UDP、有 download 目录的）→ 大概率就是它拖慢你。

**关停（以 systemd 服务为例）**：
```bash
systemctl stop <服务名>
systemctl disable <服务名>          # 禁开机自启
# 彻底卸载：删 service 文件、二进制、数据目录、专用用户
rm -f /etc/systemd/system/<服务名>.service*
systemctl daemon-reload
rm -f /usr/local/bin/<程序>
rm -rf /var/lib/<程序>              # 注意可能有几 GB 下载数据
userdel <专用用户>
find / -iname '*<程序名>*' -not -path '/proc/*' -not -path '/sys/*' 2>/dev/null  # 查残留
```

---

## 5. 验证与测速

```bash
# 确认参数生效
sysctl -n net.ipv4.tcp_congestion_control net.core.default_qdisc
sysctl -n net.core.rmem_max net.ipv4.tcp_notsent_lowat

# 服务器侧带宽自测（看上游线路本身）
apt-get install -y speedtest-cli && speedtest-cli --simple
```

**客户端实测**：用 V2rayN / Shadowrocket 等，**调优前后各测一次下载**，对比才有意义。

---

## 6. 回退

```bash
rm -f /etc/sysctl.d/99-network-performance.conf \
      /etc/sysctl.d/10-bbr.conf \
      /etc/security/limits.d/99-network-performance.conf
sysctl -w net.ipv4.tcp_congestion_control=cubic
sysctl -w net.core.default_qdisc=pfifo_fast
iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
sysctl --system
```
> 或直接用 `tcp_tune_clean.sh` 菜单选 **5 一键回退**。

---

## 7. 避坑清单

| 坑 | 说明 |
|---|---|
| `tcp_congestion_control_version = 3` | **内核里没有这个参数**，是伪参数/安慰剂，BBR3 不靠它开。别写。 |
| `tcp_ecn = 1` | 主动发起 ECN 可能被中间设备丢包导致连不上。用 `2`（被动）更稳。 |
| `tcp_retries2 = 8` | 把重传上限从默认 15 砍到 8，丢包链路上更容易断连。**不建议改**，保留默认。 |
| `rmem_default = 2097152` | 每条连接默认就吃 2MB，连接多时浪费内存。建议 256KB（`262144`），峰值交给 `rmem_max` 自动伸缩。 |
| 缓冲区不封顶 | 大内存机 5% 可能上百 MB，单连接撑太大。**封顶 64MB**。 |
| `limits.d` 对 systemd 无效 | systemd 服务的句柄要写在 service 的 `LimitNOFILE`。 |
| 网卡 ring / 队列 | NAT 小鸡常是单队列 + ring 256，是物理天花板，RPS/调参都救不了。 |
| 盲目重复调参 | 机器若已调过（bbr + 大缓冲已在），重复写只会制造冲突。**先体检**。 |
| HTTP 远程脚本 | `bash <(curl http://...)` 以 root 跑明文下载的代码有中间人风险，尽量用 https 或下载后审阅再跑。 |

---

## 8. 一次完整流程（抄作业）

1. 体检（第 1 步）→ 判断是否已调过、内核是否支持 BBR、网卡天花板。
2. 找代理（第 2 步）→ 确定走没走 UDP。
3. 补调优（第 3 步）→ **只补缺的**，独立 drop-in 文件。
4. **查抢资源的进程（第 4 步）→ 往往这步收益最大。**
5. 验证 + 客户端测速（第 5 步）→ 调优前后对比。
6. 不满意就回退（第 6 步），对照避坑清单（第 7 步）排查。
