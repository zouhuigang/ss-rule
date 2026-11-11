### AI 分流

https://github.com/h4rk8s/Surge/blob/0ba8b11adec817160a78ecc672936606bad5a5fa/Custom/generated/ai/anthropic.strict.list#L13

https://github.com/viewer12/OverseasAI.list/blob/23aa786799127f3e9b07d5ef4877080623c7e73a/rule/Surge/OverseasAI/OverseasAI_Resolve.list#L130


### claude 官方的api

https://platform.claude.com/docs/en/api/ip-addresses

### Claude 规则维护（2026-11-11）

- Shadowrocket 维护 `family/Claude.list`，由 `ss.conf` 绑定 `Claude` 分组；清单不带 URL 协议前缀或策略名。
- Quantumult X 同步维护 `quantumultx/Claude.list` 及 `quantumultx/ss-rule.list` 中的 Claude 区段，统一使用「住宅节点」。
- `claude.app` 及其子域名根据 [Desktop 官方网络要求](https://code.claude.com/docs/en/desktop#network-access-requirements) 补充；`anthropic.com`、`claude.ai`、`claude.com`、`claudeusercontent.com` 等已有后缀规则覆盖对应子域名。
- 两个 Datadog 精确域名来自 [Claude Code 官方网络要求](https://code.claude.com/docs/en/network-config#network-access-requirements)，属于可选遥测。入口可能被其他应用共用，域名规则无法按应用区分；不加入整站 Sentry、Statsig、Intercom 或 `datadog`、`sift` 关键字规则。
- `anthropic.com.cdn.cloudflare.net` 是维护者提供的兼容 CDN 条目，本次未找到官方网络清单中的确认依据，也未完成客户端实测。
- API / Console 的显式 IP 规则使用官方入站地址：`160.79.104.0/23`、`153.61.224.0/22`、`2607:6bc0::/48`。不将服务器出站范围 `160.79.104.0/21` 当作客户端访问清单，也不扩大 IPv6 到 `/32`。
- AS399358 在 [ARIN 登记](https://rdap.arin.net/registry/autnum/399358) 为 Anthropic。`IP-ASN` 作为自有网络的补充匹配，依赖客户端 ASN 数据库，不代表覆盖所有 Claude CDN。Shadowrocket 使用 `IP-ASN,399358,no-resolve`；Quantumult X 按 [官方示例](https://github.com/crossutility/Quantumult-X/blob/master/sample.conf) 使用 `IP-ASN,399358,住宅节点`。
- 本次完成文件格式、覆盖范围和三份清单一致性检查；未验证客户端导入、ASN 数据库命中或实际出口。更新远程规则后，应在客户端规则测试和连接日志中确认命中住宅分组及指定住宅节点。
- IP125 主站、首页及“我的 IP”页面的查询接口一并纳入 Claude 住宅清单，并附 2026-11-11 的 80 个目标 IP 快照（58 个 `/32`、22 个 `/128`），详见 [IP125 住宅出口分流与检测说明](../docs/ip125-claude-routing.md)。共享 CDN 地址可能影响其他无域名连接，快照随 DNS 变化需要更新。

### 分流

1、对访问IP质量要求比较高的，走住宅IP（按服务独立分组）：
   - Claude、ChatGPT 的域名按服务拆分在 family/ 目录下，各自对应配置里独立的 select 分组（Claude、ChatGPT），
     通过正则筛选实际存在的「专属纯净静态住宅节点」，同时支持「专属纯净静态住宅Ip-连接线路1」至「专属纯净静态住宅Ip-连接线路4」，
     默认选择首个匹配住宅节点，不添加阻断占位；可在各分组中手动选择住宅节点，
     住宅节点不可用时停止使用，不切换到普通代理（select 纯手动，不会自动切换）
   - IP125 主站及其探测接口在 Claude.list，Shadowrocket 优先走「Claude」分组；family_ip.list 中保留的 ip125.com 条目优先级较低
   - 其余杂项（ping0.cc、fast.com 等）在 family_ip.list，走「住宅IP」分组

2、对单纯需要梯子的，用proxy_ip.list，走代理

3、对国内访问的，用direct_ip.list，不走代理

住宅节点与 IP 检测网站分流的详细记录见 [住宅节点策略约定](../docs/residential-policy.md#ip-检测网站分流记录)。
