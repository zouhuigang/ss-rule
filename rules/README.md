### AI 分流

https://github.com/h4rk8s/Surge/blob/0ba8b11adec817160a78ecc672936606bad5a5fa/Custom/generated/ai/anthropic.strict.list#L13

https://github.com/viewer12/OverseasAI.list/blob/23aa786799127f3e9b07d5ef4877080623c7e73a/rule/Surge/OverseasAI/OverseasAI_Resolve.list#L130


### claude 官方的api

https://docs.anthropic.com/en/api/ip-addresses



### 分流

1、对访问IP质量要求比较高的，走住宅IP（按服务独立分组）：
   - Claude、ChatGPT 的域名按服务拆分在 family/ 目录下，各自对应配置里独立的 select 分组（Claude、ChatGPT），
     只引用配置内的「住宅固定出口」，真实参数由私有配置固化；线路故障不自动更换出口，恢复后继续重试同一节点。
     公开模板只有阻断占位，必须先填写含真实住宅节点的私有配置；不再依赖订阅节点排序。
   - 其余杂项（ip125.com、ping0.cc、fast.com 等）在 family_ip.list，走「住宅IP」分组

2、对单纯需要梯子的，用proxy_ip.list，走代理

3、对国内访问的，用direct_ip.list，不走代理

住宅节点与 IP 检测网站分流的详细记录见 [住宅节点策略约定](../docs/residential-policy.md#ip-检测网站分流记录)。
