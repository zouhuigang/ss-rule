# DNS 解析优化记录

基于真实访问日志（约 50 秒采样窗口，702 行）对 `ss.conf` 的 DNS 配置做的第二轮优化。

## 一、日志诊断

### 1.1 高频解析 TOP 域名

| 域名 | 50s 内解析次数 | 现象 |
|---|---|---|
| `mon.zijieapi.com` | 24 | 全部 `cache expired => 0` |
| `f2.lilybearing.com`（CF CDN，背后 ssh.github.com 等） | 14 | 代理域，远端解析 |
| `tnc0-aliec2.zijieapi.com` | 13 | 全部 `cache expired => 0` |
| `api.anthropic.com` | 5 | 走 fake-ip |
| `ssh.github.com` | 5 | 走 fake-ip |

### 1.2 关键日志事件

```
[10:42:20.810] dns query <59> system send ipv4 api100-eeft-mixed-quic-v6-hl.feishu.cn to 192.168.110.1
[10:42:20.822] dns query <59> response api100-eeft-mixed-quic-v6-hl.feishu.cn from 192.168.110.1
```

国内域名通过 `dns-direct-system = true` 路径发到了路由器（192.168.110.1），由路由器转 ISP DNS。

```
[10:43:01.495] dns socket did closed => 223.5.5.5
```

明文 UDP `223.5.5.5` 实际参与了竞速，而不是 DoH3 独占。

### 1.3 性能分布

- DNS lookup `cost` 全部 < 0.3ms（亚毫秒级，无瓶颈）
- TCP 连接超时 5s+（如 `api.anthropic.com 7562ms`、`feishu 35139ms`）— **不是 DNS 问题**，是代理出口或对端 RST

**结论**：DNS 解析本身性能 OK，但缓存失效率过高（字节系全部 expired），且部分国内 App 可能绕过加密链路。

## 二、改动清单

### 2.1 `fallback-dns-server` 异源化

**改前**：
```ini
fallback-dns-server = https://1.1.1.1/dns-query,https://cloudflare-dns.com/dns-query
```

**改后**：
```ini
fallback-dns-server = https://1.1.1.1/dns-query,https://dns.google/dns-query
```

**理由**：原配置两条都是 Cloudflare（同 IP 段同运营商），故障会同时挂。fallback 只在主 DNS 全部失败时生效，应跟主链路完全异源。换 Google 做二次兜底。

### 2.2 `hijack-dns` 增加国内公共 DNS

**改前**：
```ini
hijack-dns = 8.8.8.8:53,8.8.4.4:53,1.1.1.1:53,1.0.0.1:53
```

**改后**：
```ini
hijack-dns = 8.8.8.8:53,8.8.4.4:53,1.1.1.1:53,1.0.0.1:53,223.5.5.5:53,119.29.29.29:53,114.114.114.114:53
```

**理由**：很多国内 App（下载工具/IM/直播）硬编码 `223.5.5.5/119.29.29.29/114.114.114.114`，原配置只劫持 Google/CF，国内的没拦下来 → DoH3 加密链路被绕过，DNS 查询裸奔。

### 2.3 `[Host]` 区高频域名绑定指定 DNS

**改前**：
```ini
*.taobao.com = server:223.5.5.5
*.tmall.com = server:223.5.5.5
*.jd.com = server:119.29.29.29
*.qq.com = server:119.29.29.29
*.weixin.qq.com = server:119.29.29.29   # 冗余
*.bilibili.com = server:119.29.29.29
*.163.com = server:119.29.29.29
localhost = 127.0.0.1                    # 冗余
```

**改后**：
```ini
*.taobao.com = server:223.5.5.5
*.tmall.com = server:223.5.5.5
*.alipay.com = server:223.5.5.5
*.jd.com = server:119.29.29.29
*.qq.com = server:119.29.29.29
*.bilibili.com = server:119.29.29.29
*.163.com = server:119.29.29.29
*.zijieapi.com = server:119.29.29.29
*.feishu.cn = server:119.29.29.29
*.douyin.com = server:223.5.5.5
*.amemv.com = server:223.5.5.5
```

**理由**：
- `*.zijieapi.com` / `*.feishu.cn`：日志中 50s 查询 20+ 次，路由器返回 TTL 极短（ISP 压缩），直接绑 dnspod 走 Shadowrocket 的 DoH3 缓存链路，避免每次都走 `192.168.110.1 → ISP` 路径
- `*.douyin.com` / `*.amemv.com`：抖音高频，预防性绑定
- `*.alipay.com`：支付高频，预防性绑定
- 移除 `*.weixin.qq.com`：被 `*.qq.com` 覆盖
- 移除 `localhost = 127.0.0.1`：系统已自动解析

## 三、不动的部分（已是最优）

| 配置项 | 当前值 | 不改的原因 |
|---|---|---|
| `dns-server` | `h3://dns.alidns.com,h3://doh.pub,223.5.5.5,119.29.29.29` | DoH3 优先 + 明文 UDP 兜底，竞速 cost < 0.3ms |
| `dns-direct-system` | `true` | 国内 CDN 调度依赖客户端真实 IP；DoH3 没启用 ECS，让国内域名走系统 DNS（路由器）反而能保留就近调度 |
| `private-ip-answer` | `true` | 防止 Shadowrocket 误判劫持强制走代理 |
| `allow-dns-svcb` | `false` | 强制 A 记录查询，让 fake-ip 生效 |
| `ipv6` / `prefer-ipv6` | `false` | 关闭 AAAA 查询减少 DNS 耗时 |
| `fake-ip` 段 | 默认 `198.18.0.0/15` | 日志中工作正常 |

## 四、后续观察方向

DNS 已不是瓶颈，下一步重点是代理链路：

1. **代理出口超时**：日志中 `api.anthropic.com cost 7562ms / 9830ms`、`feishu 35139ms` 等，需要看 proxy stream 的 `did connect cost` 分布找到劣质节点
2. **`block-quic = all-proxy`** 是否影响 feishu/抖音的 QUIC 表现，可对比开关效果
3. **`住宅IP` 分组**：anthropic 走专属住宅节点，但仍出现 5s+ 超时，可能需要看节点本身的连通性测试

## 五、关联提交

- `129a987` 基于真实日志再次优化DNS
- `646c98d` 优化dns（前一轮）
