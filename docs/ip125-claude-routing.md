# IP125 住宅出口分流与检测说明

更新日期：2026-11-11。

IP125 首页通过多个第三方接口获取 IP，再调用自己的接口查询地区和运营商。只将 `ip125.com` 主站交给住宅分组，第三方探测请求仍可能走普通代理或直连，页面因此显示多个不同出口。

当前把主站、首页探测接口及备用接口统一纳入 Claude 住宅清单，使这些请求使用同一住宅策略。实际出口取决于所选节点；分流规则和节点名称都不能证明 IP 的住宅属性或纯净度。节点侧若按目标或 IP 版本使用不同出口，页面仍可能显示不同 IP。

## 首页接口清单

以下清单来自 2026-11-11 对首页的临时浏览器抓取及[页面请求脚本](https://ip125.com/_next/static/chunks/5129-649176023fa974a2.js)分析。脚本文件名随网站发布变化；“备用”表示脚本中存在，未在该次加载中触发。

| 请求 URL | 用途 | 当次证据 |
|---|---|---|
| `https://httpbin.org/ip` | 国际 IP 首选接口 | 实际请求，HTTP 200 |
| `https://ipwho.is/` | 国际 IP 备用接口 | 脚本中的备用请求 |
| `https://api.ip.sb/jsonip` | 国际 IP 备用接口 | 脚本中的备用请求 |
| `https://ip125.com/api/myip` | 国际 IP 最后备用接口 | 脚本中的备用请求 |
| `https://ipcelou-298103.appspot.com/api/ip` | 代理 IP 探测候选 | 脚本中的候选请求 |
| `https://groovy-student-432.appspot.com/` | 代理 IP 探测候选 | 实际请求，HTTP 200 |
| `https://api.duckduckgo.com/?q=ip&format=json` | 代理 IP 探测 | 实际请求，HTTP 200 |
| `https://zh.wikipedia.org/w/api.php?action=query&meta=userinfo&format=json&origin=*` | 补充代理 IP 版本探测 | 实际请求，HTTP 200 |
| `https://pubstatic.b0.upaiyun.com/?_upnode&_t=<时间戳>` | 国内出口探测 | 实际请求，HTTP 200 |
| `https://www.cloudflare-cn.com/cdn-cgi/trace` | 国内出口探测 | 实际请求，HTTP 200 |
| `https://ipv6.testipv6.cn/ip/?callback=<随机回调>` | IPv6 出口探测 | 实际脚本请求，HTTP 200 |
| `https://whois.pconline.com.cn/ipJson.jsp` | 国内 IP 备用接口 | 脚本中的备用请求 |
| `https://ip125.com/api/geo/<IP>?lang=…` | 查询已取得 IP 的地区和运营商 | 实际请求，HTTP 200 |

国际 IP 按 `httpbin.org → ipwho.is → api.ip.sb → ip125.com/api/myip` 顺序尝试，取得结果后不再继续。两个 Appspot 地址随机选一个，与 DuckDuckGo 并行探测；缺少 IPv4 或 IPv6 结果时再尝试 Wikipedia。国内探测也有随机选择及失败回退，所以单次抓包不会包含全部候选。

此处仅覆盖首页的已知 IP 获取链路。广告、统计、静态资源，以及“分流测试”“泄露测试”等其他页面的全部探测目标不在此清单中。

## 仓库中的规则和策略

| 客户端 | 文件 | 目标策略 |
|---|---|---|
| Shadowrocket | [Claude.list](../rules/family/Claude.list) | `ss.conf` 绑定的 `Claude` 分组 |
| Quantumult X 拆分版 | [Claude.list](../rules/quantumultx/Claude.list) | `住宅节点` |
| Quantumult X 融合版 | [ss-rule.list](../rules/quantumultx/ss-rule.list) 中的 Claude 区段 | `住宅节点` |

主站继续使用 `DOMAIN-SUFFIX,ip125.com`，因此 `/api/myip` 和 `/api/geo/…` 已覆盖。新增的 11 个第三方主机均使用精确 `DOMAIN` 规则；Quantumult X 对应 `HOST`。规则按主机名匹配，同一主机的所有路径都会受影响，例如访问 `zh.wikipedia.org` 的其他页面也会使用住宅出口，不限于 IP125 发起的请求。

`family_ip.list` 中保留了兼容用的 `ip125.com` 条目。Shadowrocket 在 `ss.conf` 中先加载 Claude 清单，所以正常按配置匹配时，IP125 主站优先进入 `Claude` 分组。只切换“住宅IP”分组不会改变它。Quantumult X 两份清单均使用“住宅节点”。

国内探测接口也统一进入住宅策略后，首页“国内 IP”卡片可能显示住宅节点的海外出口，不再代表本地宽带地址。卡片相同或页面提示“全局模式”是网站根据探测结果作出的判断，不能据此认定客户端的全局路由模式已改变。

住宅候选、手动选择和普通代理隔离遵循[住宅节点策略约定](residential-policy.md)。不改变策略分组，不添加普通代理兜底，不添加住宅节点缺失时的阻断占位。

## 更新和人工核对

1. 更新客户端使用的远程规则。Shadowrocket 更新 `rules/family/Claude.list`；Quantumult X 更新正在使用的拆分版或融合版。本仓库规则须排在会匹配这些域名的其他远程规则之前。
2. Shadowrocket 全局路由使用“配置”，首页选择普通节点；在 `Claude` 分组内独立选择已确认的指定住宅节点。Quantumult X 在“住宅节点”内手动选择住宅线路。
3. 重新加载 IP125 首页；必要时关闭旧页面后再打开，避免沿用旧连接和页面结果。
4. 在客户端规则测试及连接日志中检查主站和上述探测主机，确认最终策略和指定住宅节点。页面显示的 IP 应与该节点已确认的出口相符。

可直接打开下面两个地址，查看 Anthropic 服务一侧看到的 `ip=`：

- <https://api.anthropic.com/cdn-cgi/trace>
- <https://claude.ai/cdn-cgi/trace>

两个地址本次均返回包含 `ip=` 的响应，且已由 Claude 核心域名规则覆盖。`trace` 返回的是这次请求使用的 IP 版本和出口，不是 IP 信誉评分，也不能代表所有 IPv4、IPv6 连接。异常时应修复住宅线路、规则缓存或分组选择，不切换到普通代理。

没有匹配住宅节点时，应先修复订阅或节点名称。当前配置未验证空组自动阻断，不能把没有普通候选等同于必然断网。

## 连接后自动核验方案

此方案仅记录，按维护者要求暂不启用；不添加事件脚本、定时任务或自动断开、切换行为。

后续可通过连接后的检测流程请求两个 `trace` 地址，解析 `ip=`，与维护者确认的住宅出口 IP 白名单比较。白名单应区分 IPv4 和 IPv6，不从首次请求自动学习未知出口；住宅出口变动后须重新确认。白名单不使用 Anthropic 的目标服务器 IP 段或 AS399358。

| 检测结果 | 应显示的状态 |
|---|---|
| 两个请求均返回有效 IP，且各自在已确认白名单内 | 住宅出口地址核验通过 |
| 任一有效 IP 不在白名单 | 出口异常，显示实际地址及对应接口 |
| 请求超时、响应异常、没有有效 `ip=` | 无法确认出口 |
| 未配置可信白名单 | 未配置核验标准，不能判为通过 |

检测请求应遵循当前域名分流，避免强制指定节点而掩盖实际规则错误。小火箭的 `network-changed` 事件可作为候选触发方式，但本机每次启动 VPN 是否可靠触发尚未实测；也可采用快捷指令串联启动 VPN、等待及检测。即使地址核验通过，也只证明地址命中白名单，不能证明当前信誉或住宅质量。

## 验证范围

此次验证覆盖规则格式、五个指定 URL 及其他已知首页探测目标的匹配、三份 Claude 清单一致性和住宅策略保持不变。临时抓取时的出口 IP、原始响应和广告参数不写入仓库。

规则更新后的客户端实际出口尚未验证。网站后续新增接口、节点更换出口或 IPv6 路径变化时，需要重新检查请求链路。
