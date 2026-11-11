# Shadowrocket DNS 故障与回退记录

记录日期：2026-11-11。新的 DNS 策略上线后，用户反馈“都不能使用了”，并明确指出启用 `always-ip-address = true` 后有问题。按用户要求，已通过提交 [`b2fe963`](https://github.com/zouhuigang/ss-rule/commit/b2fe963) 恢复调整前的 DNS 策略，并推送至远程 `main`。客户端恢复情况待更新配置后确认。

## 变更经过

以下提交时间使用 America/New_York 时区（当日 UTC−05:00），不是客户端故障开始或恢复时间。

| 时间或阶段 | 事件 |
|---|---|
| 调整前 | 提交 `915f8b1` 使用国内主 DNS、境外备用 DNS，允许直连域名使用系统 DNS；未启用强制本地解析 |
| 2026-11-11 07:37:40 | 提交 [`e9dfe5d`](https://github.com/zouhuigang/ss-rule/commit/e9dfe5d) 更换默认及备用 DNS，增加直连和节点引导 DNS 设置，启用 `always-ip-address = true`；同时补充 IPPure 随机探测域名规则 |
| 用户反馈 | 用户多次报告服务不可用，指出上述开关有问题，随后要求恢复之前的 DNS 策略 |
| 2026-11-11 08:37:53 | 提交 `b2fe963` 恢复原有 DNS 配置，保留新增分流清单，并同步修正相关说明 |
| 仓库确认 | 已核对远程 `main` 包含回退提交；未操作客户端活动配置、节点或 VPN |

## 故障判断

`always-ip-address = true` 属于全局强制本地解析设置，影响范围不限于 Claude。用户反馈将其作为明确的问题线索，因此回退时撤销该开关。

同一提交还修改了默认、备用、直连及代理节点的 DNS 设置。这次没有逐项隔离测试，也没有取得足以定位故障的客户端 DNS 日志，不能断言所有故障都由单一开关引起。已确认的处置是撤销整批 DNS 通用参数变更，而不是只更换一个解析器。

此前对候选 DoH 入口的 HTTPS 和 DNS 应答检查，只能证明检查时入口可响应，未覆盖客户端实际解析、连接及失败回退路径，不能替代完整配置的客户端验证。

## 回退内容

| 参数 | 回退后的状态 |
|---|---|
| `dns-server` | 恢复阿里 / 腾讯 DoH3 与国内明文 DNS |
| `fallback-dns-server` | 恢复 Cloudflare / Google DoH 备用 |
| `dns-direct-system` | 从 `false` 恢复为 `true` |
| `direct-dns-server` | 移除本次新增设置 |
| `proxy-dns-server` | 移除本次新增设置 |
| `always-ip-address` | 移除启用项，恢复原有注释状态 |

恢复后的配置片段如下；最后一行是注释，不是启用设置：

```ini
[General]
dns-server = h3://dns.alidns.com/dns-query,h3://doh.pub/dns-query,223.5.5.5,119.29.29.29
fallback-dns-server = https://1.1.1.1/dns-query,https://dns.google/dns-query
dns-direct-system = true
# always-ip-address =
```

`ss.conf` 已与提交 `915f8b1` 的文件逐字节一致。Claude、ChatGPT、IP125 和 IPPure 的既有分流及新增探测域名规则保留，Quantumult X 的规则未因本次回退改变。

住宅分组保持手动选择指定住宅节点，未添加普通代理、`PROXY`、`DIRECT` 或机场节点作为候选、嵌套出口或兜底。具体约束见[住宅节点策略约定](residential-policy.md)。

## 客户端应用和复查

1. 备份客户端当前配置，再更新完整 [`ss.conf`](../ss.conf)。只更新 Claude 等远程规则集不会撤销 `[General]` 中的 DNS 设置。
2. 核对主 DNS、备用 DNS 和 `dns-direct-system` 与上方一致；移除本次新增的 `direct-dns-server`、`proxy-dns-server` 及 `always-ip-address = true`。若客户端另设了强制本地解析覆盖项，也需关闭。
3. 全局路由使用“配置”，首页选择普通节点；Claude、ChatGPT、住宅IP 分组各自手动选择实际存在的指定住宅节点。
4. 手动重新连接，分别检查国内网站、普通代理网站、Claude 和 ChatGPT 的访问及登录；结合连接日志确认住宅服务仍使用指定住宅出口。
5. 若仍不可用，记录客户端版本、目标域名、失败时间，以及对应的 DNS / 连接日志，再区分解析失败、节点连接失败与服务端拒绝。住宅线路不可用时修复住宅线路，不改走普通代理。

恢复后的配置包含国内和系统 DNS，检测页仍可能显示国内解析器。网页走住宅出口与 DNS 查询走住宅出口是不同问题；本次回退不保证 DNS 检测结果全部为境外。检测原理及 WebRTC 伪装地址说明见 [IPPure DNS 检测与分流配置](ippure-dns-routing.md)。

## 验证结果与后续维护

仓库已完成配置内容比对、差异格式检查及提交推送；客户端实际恢复、登录成功和出口检查仍待用户确认，不能将仓库回退完成记为服务已恢复。

维护时可在仓库根目录复核：

```sh
# 无输出表示当前 ss.conf 与回退前的基线内容一致
git diff 915f8b1 HEAD -- ss.conf

# 无输出表示回退提交没有改动分流清单和 Quantumult X 配置
git diff e9dfe5d b2fe963 -- rules/ quantumultx.conf

# 核对回退提交的实际修改范围
git show --stat b2fe963
```

后续如需改进按域名选择 DNS，应保留当前版本作基线，先逐项验证客户端的解析、节点连接、国内网站及住宅服务访问，再扩大应用范围。不要为了检测页全绿重新启用这次已回退的全局方案。
