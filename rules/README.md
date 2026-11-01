### AI 分流

https://github.com/h4rk8s/Surge/blob/0ba8b11adec817160a78ecc672936606bad5a5fa/Custom/generated/ai/anthropic.strict.list#L13

https://github.com/viewer12/OverseasAI.list/blob/23aa786799127f3e9b07d5ef4877080623c7e73a/rule/Surge/OverseasAI/OverseasAI_Resolve.list#L130


### claude 官方的api

https://docs.anthropic.com/en/api/ip-addresses



### 分流

1、对访问IP质量要求比较高的，走住宅IP（按服务独立分组）：
   - Claude、ChatGPT 的域名按服务拆分在 family/ 目录下，各自对应配置里独立的 select 分组（Claude、ChatGPT），
     通过正则筛选实际存在的「专属纯净静态住宅节点」，同时支持「专属纯净静态住宅Ip-连接线路1」至「专属纯净静态住宅Ip-连接线路4」，
     默认选择首个匹配住宅节点，无匹配时使用「住宅节点缺失-禁止连接」本地阻断候选；可在各分组中手动选择住宅节点，
     住宅节点不可用时停止使用，不切换到普通代理（select 纯手动，不会自动切换）
   - 其余杂项（ip125.com、ping0.cc、fast.com 等）在 family_ip.list，走「住宅IP」分组

2、对单纯需要梯子的，用proxy_ip.list，走代理

3、对国内访问的，用direct_ip.list，不走代理

住宅节点与 IP 检测网站分流的详细记录见 [住宅节点策略约定](../docs/residential-policy.md#ip-检测网站分流记录)。
