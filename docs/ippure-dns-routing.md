# IPPure DNS 检测与分流配置

更新日期：2026-11-19。此页说明 Shadowrocket 的 DNS 配置和 IPPure 探测域名的分流。

上一次启用全局强制本地解析后的故障见 [DNS 故障与回退记录](dns-rollback-2026-11-11.md)。

## 网站如何识别 DNS

[IPPure Claude 检测页](https://ippure.com/claude.html)不会直接读取设备的 DNS 设置。它的[DNS 检测脚本](https://ippure.com/assets/chunks/useDNS.D-IEVMHV.js)生成随机子域名，发起 HTTPS 请求，并从测试服务取得参与解析的递归 DNS 地址：

| 测试服务 | 随机目标 |
|---|---|
| Surfshark | `<随机值>.ipv4.surfsharkdns.com` |
| Fastly | `<随机值>.u.fastly-analytics.com/debug_resolver` |
| BrowserLeaks IPv4 | `<随机值>.dns4.browserleaks.net` |
| BrowserLeaks IPv6 | `<随机值>.dns6.browserleaks.net` |

随机名称减少已有 DNS 缓存的影响。递归解析器查询测试服务的权威 DNS 时，服务端可记录查询来源，再通过接口返回结果。页面把多家结果合并、去重并标记地区，因此可能显示多个 DNS 地址；这些不是设备的宽带出口 IP。解析器地区、DoH 请求出口与网页数据出口是三个不同概念。

## Shadowrocket 客户端 DNS

`ss.conf` 的主解析器是 Cloudflare，主解析失败或超时时使用 Google。两个 DoH 入口均使用 IP 地址，可省去解析 DoH 服务域名的步骤。

```ini
[General]
dns-server = https://1.1.1.1/dns-query
fallback-dns-server = https://8.8.8.8/dns-query
dns-direct-system = false
hijack-dns = :53
```

直连域名默认使用配置内的 DoH。原先绑定阿里、腾讯明文 DNS 的公网域名也改用该默认设置。`[Host]` 中 Apple、iCloud、Bonjour 等兼容性例外仍用系统 DNS。`hijack-dns` 针对进入 TUN 的 53 端口查询，应用自带的加密 DNS 和绕过 TUN 的流量需要另外核对。

全局强制本地解析 `always-ip-address` 保持关闭。Claude、ChatGPT 和 IPPure 的探测域名经代理连接时，住宅节点可能负责解析目标域名。客户端 DoH 配置只控制客户端发起的查询，检测页仍可能显示住宅节点侧或浏览器使用的其他解析器。

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

1. 备份当前配置，导入或替换完整 `ss.conf`。DNS 参数位于完整配置的 `[General]` 和 `[Host]` 段。
2. 全局路由使用“配置”，首页保留普通节点；Claude 分组手动选择实际存在的指定住宅节点。
3. 重连后，临时关闭测试浏览器自带的安全 DNS，打开新的 IPPure 检测页。结合 DNS 日志核对随机测试域名使用的解析器，结合连接日志核对数据请求的住宅节点。
4. 检查常用国内网站及 Claude、ChatGPT 的登录和访问。

若仍出现国内解析器，先按随机域名查 Shadowrocket 的 DNS 日志。若连接日志显示请求交给住宅节点，进一步确认节点服务端实际使用的解析器。

## WebRTC 的单独说明

`ss.conf` 保留 `stun-response-ip = 1.1.1.1`、`stun-response-ipv6 = ::1`，用于返回伪装地址。检测页出现 `1.1.1.1` 不能据此认定真实宽带 IP 泄露；页面的地区和风险标签也不能替代实际连接日志。

## 验证范围

在仓库所在机器上，Cloudflare `1.1.1.1` 和 Google `8.8.8.8` 均通过 RFC 8484 HTTPS 查询返回有效应答。实际 TUN 接管、备用 DNS 切换及住宅节点侧解析，需要在客户端导入完整配置后验证。

参考：[Google DoH 接口](https://developers.google.com/speed/public-dns/docs/doh)、[Cloudflare DoH 说明](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/)、[Shadowrocket 配置维护者的 DNS 说明](https://github.com/LOWERTOP/Shadowrocket#修改dns)。
