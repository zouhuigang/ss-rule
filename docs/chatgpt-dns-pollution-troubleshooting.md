# ChatGPT 打不开排障记录：always-real-ip 引发的 DNS 污染

时间：2026-06-06。现象：浏览器访问 `https://chatgpt.com/` 打不开（时灵时不灵），最初以为是静态住宅 IP 被 ChatGPT 封禁，实际是 DNS 污染。

## 一、排障过程

### 1.1 直接 curl 测试（暴露问题）

```
curl -sv https://chatgpt.com/
```

关键输出：

```
* Server certificate:
*  subject: CN=*.facebook.com          ← 证书是 Facebook 的！
*  subjectAltName does not match chatgpt.com
* SSL: no alternative certificate subject name matches target host name 'chatgpt.com'
```

```
dig +short chatgpt.com
31.13.87.34                            ← Meta（Facebook）的 IP 段
```

`chatgpt.com` 被解析到 Facebook 的 IP，连过去自然拿到 `*.facebook.com` 证书，TLS 校验失败，页面打不开。典型 GFW DNS 投毒。

### 1.2 验证代理链路本身是通的

通过小火箭本地 HTTP 代理端口（按域名转发，跳过本地 DNS）：

```
curl -x http://127.0.0.1:1082 https://chatgpt.com/cdn-cgi/trace
ip=192.204.2.5        ← 静态住宅节点出口（波士顿 colo=BOS）
```

**说明住宅 IP 没有被封**，只要按域名走代理、由节点远程解析，一切正常。

### 1.3 定位污染来源：小火箭的 DNS 返回了真实（污染）IP

```
dig +short chatgpt.com @198.18.0.2     # 小火箭 fake-ip DNS
31.13.87.34                            ← 返回的是真实（污染）IP，不是 fake-ip！

dig +short claude.ai @198.18.0.2       # 对照组
198.18.0.16                            ← 正常的 fake-ip
```

差异原因：`ss.conf` 的 `always-real-ip` 里包含了 `chatgpt.com,*.openai.com` 等域名（2026-06-02 提交 `9a79fb3` 顺手加入，无记录原因），而 `claude.ai` 不在名单里。

### 1.4 故障链完整还原

```
chatgpt.com 在 always-real-ip 名单里
        ↓
小火箭不返回 fake-ip，转而用上游 DNS 解析真实 IP
        ↓
上游是国内 DNS（h3://dns.alidns.com、doh.pub）→ 对 chatgpt.com 返回污染结果 31.13.87.34
        ↓
浏览器拿着 Facebook 的 IP 发起连接（即使经过代理，也是连到真 Facebook 服务器）
        ↓
证书 *.facebook.com 与 chatgpt.com 不匹配 → 打不开
```

"时灵时不灵"的原因：污染并非每次命中（如 `auth.openai.com` 经 CNAME `auth.openai.com.cdn.cloudflare.net` 偶尔能解析到正确的 Cloudflare IP）。

## 二、修复

从 `always-real-ip` 移除 `auth.openai.com,api.openai.com,chatgpt.com,*.openai.com,*.chatgpt.com` 五项，恢复 fake-ip 模式（修改在 `ss.conf` [General] 区，已加注释说明）。

fake-ip 模式下的正确工作流程：

```
浏览器查询 chatgpt.com → 小火箭返回 fake-ip（198.18.x.x）
        ↓
连接进入 TUN，按 fake-ip 反查域名 → 命中 DOMAIN-SUFFIX 规则 → ChatGPT 分组
        ↓
域名（不是 IP）发给代理节点，由节点在境外远程解析 → 天然免疫 DNS 污染
```

## 三、经验教训

1. **走代理的域名绝不能放进 `always-real-ip`**。该选项只适合必须直连且对 fake-ip 敏感的服务（Apple 推送、STUN、Xbox 等）。强制真实 IP = 强制本地解析，在国内 DNS 上游下等于主动接受污染。
2. **"打不开"不一定是 IP 被封**。先 `curl -v` 看证书域名是否匹配、`dig` 看解析结果是否在合理 IP 段，再下结论。本次住宅 IP 全程无辜。
3. **改 DNS 相关配置要单独提交并写明原因**。`9a79fb3` 把 `always-real-ip` 改动混在 VPS 调优文档提交里且无说明，排障时只能靠 `git log -S` 考古。
4. 对照实验很有效：同类服务一个正常（claude.ai）一个异常（chatgpt.com），对比两者配置差异能快速锁定根因。

## 四、快速自检命令

下次再遇到某站点打不开，依次执行：

```bash
# 1. 看解析到哪了（污染 IP 常见特征：Facebook/Twitter 的段、127.0.0.1、保留段）
dig +short 目标域名

# 2. 看小火箭 DNS 返回 fake-ip 还是真实 IP（fake-ip = 198.18.x.x 为正常）
dig +short 目标域名 @198.18.0.2

# 3. 跳过本地 DNS、按域名走代理测试（通 = 链路和节点没问题，问题在本地 DNS）
curl -x http://127.0.0.1:1082 https://目标域名/cdn-cgi/trace

# 4. 看证书发给谁（证书域名不匹配 = 连错了服务器 = DNS 污染）
curl -sv https://目标域名/ -o /dev/null 2>&1 | grep "subject:"
```
