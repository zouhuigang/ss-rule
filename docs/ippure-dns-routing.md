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

## Shadowrocket 已恢复原 DNS 策略

2026-11-11，用户反馈新的 DNS 策略导致服务不可用，并指出启用 `always-ip-address = true` 后出现问题。现已将 `ss.conf` 完整恢复到提交 `915f8b1` 的版本，撤销本次 DNS 通用参数变更，保留新增的 Claude / IPPure 分流规则。具体故障原因尚未通过客户端日志确认。

当前 `ss.conf` 使用以下设置：

```ini
[General]
dns-server = h3://dns.alidns.com/dns-query,h3://doh.pub/dns-query,223.5.5.5,119.29.29.29
fallback-dns-server = https://1.1.1.1/dns-query,https://dns.google/dns-query
dns-direct-system = true
# always-ip-address =
```

| 查询用途 | 指定处理方式 |
|---|---|
| 客户端需要解析的目标 | 阿里 / 腾讯 DoH3 与国内明文 DNS；失败时使用原有境外 DoH 备用 |
| 明确命中直连域名规则的国内目标 | 允许系统 DNS；已有国内 `[Host]` 数字 DNS 绑定继续保留 |
| Claude、IPPure 探测域名及其他代理目标 | 不再强制客户端先解析所有代理目标；实际解析位置和解析器需结合客户端及节点行为核对 |
| 代理节点自身的主机名 | 撤销本次新增的 `proxy-dns-server`，恢复原有处理方式 |
| Apple、Bonjour 等现有 `server:system` 特例 | 继续使用系统解析，不把这些局域网 / 系统服务统一送到公共 DNS |

`always-ip-address` 已恢复为原有注释状态，不再显式启用全局强制本地解析。同时移除本次新增的 `direct-dns-server`、`proxy-dns-server`，恢复原来的主 DNS、备用 DNS 和 `dns-direct-system = true`。

恢复后的策略包含国内、系统及明文 DNS，因此 IPPure 仍可能显示国内解析器。**网页走 Claude 住宅出口，不代表 DNS 查询也经住宅出口。** 本次回退旨在恢复原有解析行为，不保证检测页全部显示境外 DNS；也没有将普通代理或直连添加为住宅分组的候选或兜底。

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
3. 核对主 DNS、备用 DNS 和 `dns-direct-system` 与上方一致，移除本次新增的直连 DNS、代理节点 DNS 及 `always-ip-address = true`。如果客户端另有“强制本地解析”覆盖设置，也需自行关闭。
4. 用户手动重新连接后，关闭旧检测页并新开页面重测，结合 DNS 日志核对随机测试域名使用的解析器，结合连接日志核对数据请求的住宅节点。
5. 检查国内购物、视频和工作网站，以及 Claude、ChatGPT 的图片、视频和登录是否恢复。

如果检测结果仍包含国内解析器，先按随机查询对应的 DNS 日志查明是浏览器自带 DNS、规则顺序、系统特例、客户端失败回退还是节点侧行为。不要靠屏蔽测试服务、篡改结果或重新标注国家让页面变绿。

## WebRTC 的单独说明

`ss.conf` 保留 `stun-response-ip = 1.1.1.1`、`stun-response-ipv6 = ::1`，用于返回伪装地址。检测页出现 `1.1.1.1` 不能据此认定真实宽带 IP 泄露；页面的地区和风险标签也不能替代实际连接日志。

## 验证范围

先前曾验证新方案的六个 DoH 入口可通过 RFC 8484 GET 请求返回 HTTPS / DNS 应答；该检查未覆盖客户端实际采用配置后的行为，不能证明新方案可用。用户反馈故障后，现已撤销该方案。

回退检查核对 `ss.conf` 与提交 `915f8b1` 完全一致，Claude 清单及住宅分组没有因本次回退而更改。未切换活动客户端配置或 VPN，恢复后的实际可用性仍需用户更新后确认。

参考：[Google DoH 接口](https://developers.google.com/speed/public-dns/docs/doh)、[Cloudflare DoH 说明](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/)、[Shadowrocket 配置维护者的 DNS 说明](https://github.com/LOWERTOP/Shadowrocket#修改dns)。
