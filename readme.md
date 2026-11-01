# ss-rule

个人分流规则仓库，同时支持 **Shadowrocket（小火箭）** 和 **Quantumult X**。

核心思路：对 IP 质量要求高的服务（Claude、ChatGPT 等）走**住宅/静态 IP**，且**按服务独立分组**。住宅分组只允许选择住宅节点；住宅节点不可用时停止使用，不切换到普通代理。

住宅策略的长期维护约束见 [住宅节点策略约定](docs/residential-policy.md)。

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

基于 [LOWERTOP/Shadowrocket](https://github.com/LOWERTOP/Shadowrocket) 配置，采用固定住宅出口分流。

公开模板：<https://raw.githubusercontent.com/zouhuigang/ss-rule/refs/heads/main/ss.conf>

**公开模板不含住宅凭据，住宅连接默认阻断。** 需要将确认的住宅节点固化到私有配置后使用，不能再直接下载公开模板覆盖私有配置。

1. 将模板另存为设备私有配置，例如 `ss-residential-private.conf`。
2. 只将 `[Proxy]` 中「住宅固定出口」的占位参数替换为确认可用的真实住宅节点参数（协议、地址、端口、认证和 TLS 等必须完整保留）。
3. 私有配置移除整份更新地址 `update-url`，防止公开模板覆盖本地住宅参数。
4. 使用时全局路由保持「配置」，首页选择普通专线；核对 Claude、ChatGPT、ip125.com、ping0.cc 的规则及真实出口。

```ini
[Proxy Group]
Claude = select,住宅固定出口,policy-select-name=住宅固定出口
ChatGPT = select,住宅固定出口,policy-select-name=住宅固定出口
住宅IP = select,住宅固定出口,policy-select-name=住宅固定出口
代理IP = select,PROXY,policy-select-name=PROXY
```

「住宅固定出口」的真实定义必须保存在同一私有配置的 `[Proxy]` 中。源节点名称支持旧名称和线路1～4；不自动换线。断网时连接失败，恢复后新请求继续使用原节点；订阅重命名不影响快照。节点凭据变动须人工确认后更新。

住宅域名在本地内置，远程规则未下载时也有本地规则。普通代理流量跟随首页节点。私有文件包含凭据，禁止上传或分享；更新规则需合并到私有配置，并保留固定出口参数。详见 [策略文档](docs/residential-policy.md)。

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
static = 代理IP, proxy
static = Claude, 住宅节点
static = ChatGPT, 住宅节点
static = 住宅IP, 住宅节点
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
