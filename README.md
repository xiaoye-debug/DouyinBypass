# DouyinBypass v2.0.0

iOS 抖音插件：绕过版本检测 + 账号备份/恢复

## 功能

### 1. 绕过检测（v1.0 原有）
- mobileprovision 签名验证绕过
- 强制升级弹窗拦截
- App Store 渠道伪装
- 证书校验跳过

### 2. 账号管理（v2.0 新增）
- **一键导出**：提取当前登录账号的完整信息（UserDefaults、Keychain、Cookies），打包为 ZIP 保存到 `/var/mobile/Documents/DouyinAccountBackup/`
- **一键导入**：从 ZIP 备份恢复账号登录状态，重启抖音即可生效
- **备份管理**：查看已保存的备份列表、清除所有备份
- **设置页注入**：在抖音设置页面底部添加「🔐 账号管理」按钮，点击进入管理界面

### 导出的数据包含
| 类别 | 内容 |
|------|------|
| UserDefaults | session_key, uid, device_id, token, login_type 等 |
| Keychain | douyin/aweme/bytedance 相关的密钥条目 |
| Cookies | douyin.com, snssdk.com, bytedance.com 等域名 |
| Metadata | 导出时间、App 版本、设备型号 |

## 安装

### 越狱设备（DEB）
```bash
make package FINALPACKAGE=1
# 将 packages/*.deb 传输到手机并安装
```

### IPA 注入（Dylib）
```bash
make package-all
# 使用 inject.sh 或手动将 packages/DouyinBypass.dylib 注入 IPA
```

## 依赖
- mobilesubstrate
- zip（系统自带 `/usr/bin/zip` 和 `/usr/bin/unzip`）

## 使用说明
1. 安装插件后打开抖音
2. 进入「我」→「设置」
3. 点击底部的红色「🔐 账号管理」按钮
4. 选择「导出当前账号信息」或「导入账号信息」
5. 导入成功后重启抖音即可切换账号

## 备份文件位置
```
/var/mobile/Documents/DouyinAccountBackup/douyin_account_<timestamp>.zip
```

可通过 Filza / SFTP / iFile 等工具访问和管理备份文件。

## 注意事项
- 导入账号后需要**重启抖音**才能生效
- 不同设备的 device_id 可能影响部分风控策略
- 备份文件包含敏感凭据，请妥善保管
- 仅适用于已越狱设备或自签 IPA 环境
