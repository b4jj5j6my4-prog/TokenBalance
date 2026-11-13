# TokenBalance

TokenBalance 是一个面向 RootHide 的 iOS 越狱插件，在 SpringBoard 上显示第三方 API 中转站的余额、总额度与已用额度。

## 功能

- SpringBoard 全局余额浮窗
- 支持拖动、折叠与四角缩放
- 自动探测常见余额接口
- 支持自定义 JSON 字段路径
- PreferenceLoader 设置面板
- 控制中心开关模块
- 配置变更通过 Darwin 通知即时生效
- 主插件、设置面板和控制中心模块均构建为 `arm64 + arm64e`

## 兼容性

- iOS 15.0 或更高版本
- RootHide 越狱环境
- 软件包架构：`iphoneos-arm64e`
- 注入目标：`com.apple.springboard`

本项目目前不支持 rootless 或 rootful。

## 支持的接口

填写平台根地址时，插件会尝试探测以下常见路径：

- `/v1/usage`
- `/api/usage/token`
- `/api/user/self`
- `/dashboard/billing/credit_grants`
- `/dashboard/billing/subscription`

也可以填写完整的 HTTPS 接口地址，并在设置中指定余额、总额和已用额度的 JSON 字段路径。

不同平台的账户接口并不统一，能否读取余额取决于平台是否提供相应 API，以及 API Key 是否有查询权限。

## 隐私

- API Key 保存在设备本地的插件偏好中
- API Key 不写入运行日志
- 仓库不包含任何 API Key、账户令牌或用户配置
- 提交代码前请勿把真实凭据写入源码、配置文件或问题报告

## 构建

需要安装支持 RootHide 的 Theos、iOS 16.5 SDK，以及 `roothide` 相关构建支持。

```sh
export THEOS=/var/mobile/theos
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

## 安装

安装生成的 `iphoneos-arm64e` 软件包后重启 SpringBoard。随后可以在 iOS 设置中配置接口与显示方式，并在控制中心添加 TokenBalance 模块。

## 项目结构

- `Tweak.xm`：浮窗、余额请求与解析逻辑
- `ShijianTokenBalancePrefs/`：PreferenceLoader 设置面板
- `ShijianTokenBalanceCC/`：控制中心开关模块
- `layout/`：PreferenceLoader 入口

## 许可证

本项目使用 GNU General Public License v3.0，详见 `LICENSE`。
