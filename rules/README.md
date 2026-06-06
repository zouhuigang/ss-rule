### AI 分流

https://github.com/h4rk8s/Surge/blob/0ba8b11adec817160a78ecc672936606bad5a5fa/Custom/generated/ai/anthropic.strict.list#L13

https://github.com/viewer12/OverseasAI.list/blob/23aa786799127f3e9b07d5ef4877080623c7e73a/rule/Surge/OverseasAI/OverseasAI_Resolve.list#L130


### claude 官方的api

https://docs.anthropic.com/en/api/ip-addresses



### 分流

1、对访问IP质量要求比较高的，走住宅IP（按服务独立分组）：
   - Claude、ChatGPT 的域名按服务拆分在 family/ 目录下，各自对应配置里独立的 select 分组（Claude、ChatGPT），
     默认走「专属纯净静态住宅节点」；某个服务把住宅IP封了时，在小火箭首页单独把该服务的分组
     手动切到「代理IP」，其他服务不受影响；恢复后手动切回住宅节点（select 纯手动，不会自动切换）
   - 其余杂项（ip125、fast.com 等）在 family_ip.list，走「住宅IP」分组

2、对单纯需要梯子的，用proxy_ip.list，走代理

3、对国内访问的，用direct_ip.list，不走代理