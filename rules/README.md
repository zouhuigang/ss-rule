### AI 分流

https://github.com/h4rk8s/Surge/blob/0ba8b11adec817160a78ecc672936606bad5a5fa/Custom/generated/ai/anthropic.strict.list#L13

https://github.com/viewer12/OverseasAI.list/blob/23aa786799127f3e9b07d5ef4877080623c7e73a/rule/Surge/OverseasAI/OverseasAI_Resolve.list#L130


### claude 官方的api

https://docs.anthropic.com/en/api/ip-addresses



### 分流

1、对访问IP质量要求比较高的，直接用family_ip.list，走住宅IP

2、对单纯需要梯子的，用proxy_ip.list，走代理

3、对国内访问的，用direct_ip.list，不走代理