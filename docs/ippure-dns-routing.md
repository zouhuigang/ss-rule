# IPPure DNS 检测与分流配置

更新日期：2026-11-11。此页说明 Shadowrocket 的 DNS 配置；Quantumult X 仅同步探测域名的住宅分流，不声称具备相同的 DNS 行为。

## 网站如何识别 DNS

[IPPure Claude 检测页](https://ippure.com/claude.html)不会直接读取设备的 DNS 设置。它的[DNS 检测脚本](https://ippure.com/assets/chunks/useDNS.D-IEVMHV.js)生成随机子域名，发起 HTTPS 请求，并从测试服务取得参与解析的递归 DNS 地址：

| 测试服务 | 随机目标 |
|---|---|
| Surfshark | `<随机值>.ipv4.surfsharkdns.com` |
| Fastly | `<随机值>.u.fastly-analytics.com/debug_resolver` |
| BrowserLeaks IPv4 | `<随机值>.dns4.browserleaks.net` |
| BrowserLeaks IPv6 | `<随机值>.dns6.browserleaks.net` |

随机名称减少已有 DNS 缓存的影响。递归解析器查询测试服务的权威 DNS 时，服务端可记录查询来源，再通过接口返回结果。页面把多家结果合并、去重并标记地区，因此可能显示多个 DNS 地址；这些不是设备的宽带出口 IP。解析器地区、DoH 请求出口与网页数据出口是三个不同概念。

## Shadowrocket 的分流 DNS

当前 `ss.conf` 使用以下设置：

```ini
[General]
dns-server = https://1.1.1.1/dns-query,https://8.8.8.8/dns-query
direct-dns-server = https://dns.alidns.com/dns-query,https://doh.pub/dns-query
fallback-dns-server = https://1.0.0.1/dns-query,https://8.8.4.4/dns-query
proxy-dns-server = https://dns.alidns.com/dns-query,https://doh.pub/dns-query
dns-direct-system = false
always-ip-address = true
```

| 查询用途 | 指定处理方式 |
|---|---|
| Claude、IPPure 探测域名及其他代理目标 | 客户端使用默认的 Cloudflare / Google DoH 解析，再通过规则选定的节点连接所得 IP |
| 明确命中直连域名规则的国内目标 | 国内 DoH；已有国内 `[Host]` 数字 DNS 绑定继续保留，这些专用绑定不宣称改为加密解析 |
| 需要先解析才能判断 IP / GEOIP 的未知目标 | 默认的境外 DoH，不保证识别为国内之前就使用国内解析器 |
| 代理节点自身的主机名 | `proxy-dns-server` 指定的国内 DoH，属于连接节点前的引导解析 |
| Apple、Bonjour 等现有 `server:system` 特例 | 继续使用系统解析，不把这些局域网 / 系统服务统一送到公共 DNS |

`always-ip-address = true` 用于强制客户端解析目标，减少代理端自行选择 DNS 的影响。它影响所有代理服务的解析和 CDN 选路，不是仅针对 Claude 的开关；代理数据仍由原有服务分组决定出口。解析位置改变后，部分 CDN、IP/GEOIP 分流或应用可能表现不同，需要在客户端更新后验证。

主、备用解析器使用 IP 形式的 HTTPS URL，避免解析这些服务域名时先依赖系统 DNS。配置中没有把 `#proxy=Claude` 当作已验证的 DNS 转发参数，也没有指定首页普通代理作为住宅 DNS 的兜底。**选择境外 DNS 服务不等于 DoH 请求本身已经通过住宅出口**，也不能保证解析器每次都被地理库标为境外；DNS 查询出站、失败回退及实际解析器需结合客户端日志验证。

不修改 `always-real-ip` 来强制 Claude 域名走国内 DNS；相关污染历史见 [ChatGPT DNS 污染排查](chatgpt-dns-pollution-troubleshooting.md)。不将住宅分组改为自动测速、普通代理或直连候选。住宅节点缺失时的客户端行为仍未验证为自动阻断。

## 探测请求的住宅分流

四类测试域名加入 `rules/family/Claude.list`。Shadowrocket 通过 `ss.conf` 的远程规则绑定到 `Claude` 分组；Quantumult X 拆分版及融合版同样补充这四类后缀，使用“住宅节点”。

```ini
DOMAIN-SUFFIX,ipv4.surfsharkdns.com
DOMAIN-SUFFIX,u.fastly-analytics.com
DOMAIN-SUFFIX,dns4.browserleaks.net
DOMAIN-SUFFIX,dns6.browserleaks.net
```

后缀只覆盖测试服务专用域名，不将整个 `fastly-analytics.com`、`browserleaks.net` 或其他服务商域名全部改走住宅。既有 `DOMAIN-SUFFIX,ippure.com` 覆盖检测页主站。

## 更新和核对

1. 在客户端备份当前配置后，手动更新完整 `ss.conf`；只更新 Claude 规则集不会应用 DNS 通用参数的变更。本次仓库修改没有切换客户端活动配置、节点或 VPN。
2. 全局路由使用“配置”，首页保留普通节点；Claude 分组手动选择实际存在的指定住宅节点。
3. 核对客户端“通用”里的默认、直连、备用 DNS 与上方一致。关闭浏览器自带的自定义安全 DNS，使本次测试采用系统 / 小火箭的解析路径；浏览器设置需要用户自行操作。
4. 用户手动重新连接后，关闭旧检测页并新开页面重测，结合 DNS 日志核对随机测试域名使用的解析器，结合连接日志核对数据请求的住宅节点。
5. 检查国内购物、视频和工作网站是否仍命中直连，并抽查图片、视频和登录。国内专用 DNS 减少选路影响，但不能保证所有国内目标完全没有变化。

如果检测结果仍包含国内解析器，先按随机查询对应的 DNS 日志查明是浏览器自带 DNS、规则顺序、系统特例、客户端失败回退还是节点侧行为。不要靠屏蔽测试服务、篡改结果或重新标注国家让页面变绿。

## WebRTC 的单独说明

`ss.conf` 保留 `stun-response-ip = 1.1.1.1`、`stun-response-ipv6 = ::1`，用于返回伪装地址。检测页出现 `1.1.1.1` 不能据此认定真实宽带 IP 泄露；页面的地区和风险标签也不能替代实际连接日志。

## 验证范围

新增前已通过 RFC 8484 GET 请求验证六个 DoH 入口的 HTTPS 证书及 DNS 应答：均返回 HTTP 200、DNS RCODE 0，并取得 `claude.ai` 的应答。这只证明检查时这些入口可访问，不证明客户端采用新配置后的解析、转发和失败回退行为。

静态检查覆盖通用参数唯一性、主备 DNS 不含国内 / 系统解析器、国内专用解析器保留、四类随机探测域名的住宅分流，以及三份 Claude 清单一致性。尚未在活动客户端启用新 DNS 配置，也未确认 IPPure 更新后的实际结果。

参考：[Google DoH 接口](https://developers.google.com/speed/public-dns/docs/doh)、[Cloudflare DoH 说明](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/)、[Shadowrocket 配置维护者的 DNS 说明](https://github.com/LOWERTOP/Shadowrocket#修改dns)。
