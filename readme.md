# ss-rule

个人分流规则仓库，同时支持 **Shadowrocket（小火箭）** 和 **Quantumult X**。

核心思路：对 IP 质量要求高的服务（Claude、ChatGPT 等）走**住宅/静态 IP**，且**按服务独立分组** —— 某个服务的住宅 IP 被封时，在首页单独把该服务切到「代理IP」，不影响其他服务；恢复后再切回。

## 目录结构

```
ss.conf                     Shadowrocket 完整配置（含策略组）
quantumultx.conf            Quantumult X 完整配置（不含订阅，需自行添加）
rules/
├── family/                 按服务拆分的住宅IP规则（Shadowrocket/Surge 格式）
│   ├── Claude.list
│   └── ChatGPT.list
├── family_ip.list          其余需要住宅IP的杂项（ip125、fast.com 等）
├── proxy/                  需要走代理的服务（AI.list、YouTube.list）
├── direct/direct_ip.list   直连（lilybearing、aliyun、Tailscale）
└── quantumultx/            上述规则的 Quantumult X 原生格式版本
    ├── ss-rule.list        ⭐ 融合版：全部规则按优先级合并，一条链接搞定
    └── *.list              各服务单独拆分版
docs/                       DNS 优化、防污染排查笔记
optimize/                   VPS TCP 调优
```

---

## Shadowrocket 使用

懒人配置，含策略组，开箱即用（基于 [LOWERTOP/Shadowrocket](https://github.com/LOWERTOP/Shadowrocket) 懒人配置修改）。

配置地址：<https://raw.githubusercontent.com/zouhuigang/ss-rule/refs/heads/main/ss.conf>

![二维码](https://raw.githubusercontent.com/zouhuigang/ss-rule/refs/heads/main/figure/ss.png)

**导入方法**：
- 方法一：用 Safari 或 Shadowrocket 扫描上方二维码；
- 方法二：Shadowrocket → 配置 → 右上角 ➕ → 粘贴配置地址 → 下载。

导入后在 `ⓘ → 代理分组` 中把 Claude / ChatGPT / 住宅IP 分组指到你的住宅节点。最好断开重连一次让规则生效。

**分流方式说明**：

```
[Proxy Group]
Claude = select,专属纯净静态住宅节点,代理IP
[Rule]
RULE-SET,https://raw.githubusercontent.com/zouhuigang/ss-rule/refs/heads/main/rules/family/Claude.list,Claude
```

`select` 为纯手动切换（不会自动切走，保证 IP 纯净度可控）；`RULE-SET` 后跟规则文件地址和分组名。

---

## Quantumult X 使用

### 方式一：完整配置（推荐新装）

配置地址：<https://raw.githubusercontent.com/zouhuigang/ss-rule/refs/heads/main/quantumultx.conf>

设置 → 配置文件 → 下载/替换。已内置策略组、DNS（DoH3 防污染）、分流引用，**不含节点订阅**，导入后需要：

1. 添加自己的节点订阅（节点 → 节点资源 → 引用，或编辑 `[server_remote]`）；
2. 住宅/静态 IP 节点的名称需包含 `住宅 / 静态 / 家宽 / Residential / Static / ISP` 任一关键词，「住宅节点」分组按正则自动识别；
3. 首页勾选一个主力节点（内置 `proxy` 策略与 `final` 兜底跟随该选择）。

### 方式二：只订阅分流规则（保留自己现有配置）

风车 → 分流 → 引用，添加融合版规则集（**不要设置「策略偏好」**，每行自带策略）：

```
https://raw.githubusercontent.com/zouhuigang/ss-rule/refs/heads/main/rules/quantumultx/ss-rule.list
```

需要配置文件 `[policy]` 中存在这些策略组（名称一致）：`Claude`、`ChatGPT`、`住宅IP`、`代理IP`、`Max`（`direct`/`proxy`/`reject` 为内置）。参考写法：

```ini
[policy]
static = 住宅节点, server-tag-regex=住宅|静态|家宽|Residential|Static|ISP
static = 代理IP, proxy, 住宅节点
static = Claude, 住宅节点, 代理IP
static = ChatGPT, 住宅节点, 代理IP
static = 住宅IP, 住宅节点, 代理IP
static = Max, proxy
```

也可以按服务单独订阅 `rules/quantumultx/` 下的拆分版（Claude.list、ChatGPT.list、AI.list、YouTube.list、direct_ip.list、family_ip.list）。

### ⚠️ 注意事项

- QX 中 `filter_remote` **先于** `filter_local` 匹配，且引用列表**自上而下**依次匹配；
- 若同时订阅了其他规则集（如 blackmatrix7 的 Global.list —— 它同样含 anthropic/claude/openai 域名），**本仓库的规则必须排在它们上面**，否则 Claude/ChatGPT 会被抢先匹配走普通代理而不是住宅 IP；
- QX 的策略组无法在图形界面创建，只能写在配置文件 `[policy]` 段中。

---

## 与 Shadowrocket 的差异（QX 版）

| ss.conf (Shadowrocket) | Quantumult X 等价实现 |
|---|---|
| `[Proxy Group]` select / url-test | `[policy]` static / url-latency-benchmark |
| `RULE-SET` 远程规则 | `[filter_remote]` 引用 |
| `[Host]` `server:system` / `always-real-ip` | `[general]` `dns_exclusion_list` |
| `dns-server = h3://...`（DoH3） | `[dns]` `prefer-doh3` + `doh-server` |
| `tun-excluded-routes` | `[general]` `excluded_routes` |
| `udp-policy-not-supported-behaviour` | `[general]` `fallback_udp_policy` |
| `PROCESS-NAME` 规则 | 不支持（本身在 iOS 上也无效），Tailscale 靠 CGNAT 网段 IP 规则直连 |

## 参考

- [LOWERTOP/Shadowrocket 懒人配置](https://github.com/LOWERTOP/Shadowrocket)
- [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script)
- [Anthropic 官方 API IP 段](https://docs.anthropic.com/en/api/ip-addresses)
- [Shadowrocket-ADBlock-Rules-Forever](https://johnshall.github.io/Shadowrocket-ADBlock-Rules-Forever/lazy_group.conf)
- 规则自动更新[捷径](https://www.icloud.com/shortcuts/20bd590bc99e4ef0a157d2fe6e8c273d)（Shadowrocket 用）
