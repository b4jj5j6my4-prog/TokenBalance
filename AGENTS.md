# 工程说明

这是一个仅面向 RootHide 的 SpringBoard 插件，使用 RootHide Theos 构建。

- 插件目标：`ShijianTokenBalance`
- 包标识：`com.shijian.tokenbalance`
- 软件包架构：`iphoneos-arm64e`
- Mach-O 切片：`arm64 + arm64e`
- 最低系统：iOS 15.0
- 注入目标：`com.apple.springboard`
- 设置面板：`ShijianTokenBalancePrefs`，通过 PreferenceLoader 显示
- 控制中心模块：`ShijianTokenBalanceCC`
- 配置域：`com.shijian.tokenbalance`
- Apelin 构建入口：`build.sh`

通过 Apelin 的项目构建功能运行 `build.sh`。脚本使用 `$THEOS`，未设置时采用逻辑路径 `/var/mobile/theos`，并将唯一的 deb 写入 `$APELIN_PACKAGE_DIR`。

构建成功后核对主插件、设置面板和控制中心模块均包含 `arm64` 与 `arm64e`，并确认 deb 的 `Architecture` 仍为 `iphoneos-arm64e`。
