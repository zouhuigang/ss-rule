### 参考
https://johnshall.github.io/Shadowrocket-ADBlock-Rules-Forever/lazy_group.conf


## 规则使用方法

方法一：用 Safari 或 ShadowRocket 扫描二维码即可。  
方法二：在 ShadowRocket 应用中，进入 [配置] 页面，点击右上角加号，将规则文件地址粘贴到 url 处，点击“下载”即可。

最好让 ShadowRocket 断开并重新连接一次，以确保新的规则文件生效。 

## 如何自动更新
步骤一：安装[捷径](https://www.icloud.com/shortcuts/20bd590bc99e4ef0a157d2fe6e8c273d)，并填写规则文件地址；  
步骤二：打开“快捷指令”下方的“自动化”，轻击右上角加号，点击“创建个人自动化”，选择“特定时间”，设定时间为 8:05 或更晚的时间（规则生成需要一定时间），点击下一步，点击添加操作，选择 APP 栏，找到快捷指令，选择“运行快捷指令”，点击浅色“快捷指令”，选择“Shadowrocket 规则自动更新”，点击下一步，关闭运行前询问（可选），点击完成即可。

如果出现无法正常跳转 Safari 对 google.cn 的请求的情况，请在每次更新后点击规则后方的ℹ️，点击 HTTPS 解密，将 HTTPS 解密关闭，返回，再开启，即可正常跳转。

## 懒人配置-含策略组（同步自 [LOWERTOP/Shadowrocket](https://github.com/LOWERTOP/Shadowrocket)）

不折腾，开箱即用。下载规则后可在 i -> 代理分组 中自行配置。

- 配置简洁
- 规则覆盖范围广
- 国内外常用app单独分流
- 添加自动切换延迟最低节点类型
- 通过「代理分组」灵活调整流媒体分流策略

规则地址：<https://raw.githubusercontent.com/zouhuigang/ss-rule/refs/heads/main/lazy_group.conf>

![二维码](https://raw.githubusercontent.com/zouhuigang/ss-rule/refs/heads/main/figure/ss.png)

