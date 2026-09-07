# Mug Uninstaller

macOS 应用卸载工具（类 Geek）：卸载应用的同时，找出该应用创建的目录与文件，逐项勾选确认后清理。

## 功能

- **应用清单**：扫描 `/Applications` 与 `~/Applications`，显示图标、版本、安装来源（App Store / Homebrew / pkg / 直接安装）、占用大小、运行状态、SIP 保护标记
- **残留扫描**：按 bundle id + 名称变体 + 厂商目录扫描 `~/Library` 与 `/Library` 全规则路径（偏好设置、缓存、日志、容器、LaunchAgents/Daemons、PrivilegedHelperTools、pkg 回执等），按 **高/中/低置信度** 分组
- **确认后卸载**：逐项勾选 → 退出进程 → `launchctl bootout` → `pkgutil --forget` → **移入废纸篓**（可恢复）；root 文件按单次操作弹管理员授权；删除路径白名单守卫
- **系统应用保护**：SIP 应用标记不可卸载（垃圾桶禁用图标）
- **GUI**：SwiftUI，跟随系统明暗，支持搜索、隐藏系统应用

## 下载安装

在 [Releases](../../releases) 下载 `MugUninstaller-v*-macOS.zip` 解压后拖入"应用程序"。

> ⚠️ 当前版本为 ad-hoc 签名、未公证：首次打开如被 Gatekeeper 拦截，请**右键点击 App → 打开**（或 `xattr -dr com.apple.quarantine MugUninstaller.app`）。
> 正式分发版将配置 Developer ID 签名 + 公证（见 `release.yml` 内注释）。

## 构建（GitHub Actions，推荐）

- **推送 / PR**：`ci.yml` 自动编译 + CLI 冒烟测试
- **打标签发版**：`git tag v0.1.0 && git push --tags` → `release.yml` 自动构建 arm64+x86_64 通用包、打包 `.app` 与 CLI、发布到 Releases

本地构建（需要完整 Xcode）：

```bash
swift build -c release
./build.sh && ./build-gui.sh   # 无 Xcode 环境下的替代脚本
```

## 用法

```bash
# GUI：open .build/release/MugUninstaller.app（或 Releases 里的 App）
# CLI：
.build/release/mug-uninstaller-cli list
.build/release/mug-uninstaller-cli scan <app路径|bundle id>
.build/release/mug-uninstaller-cli uninstall <app|bundle id> [--confirm]   # 默认干跑
```

## 结构

- `Sources/MugUninstallerKit/`：核心库（AppScanner / LeftoverScanner / UninstallEngine）
- `Sources/mug-uninstaller/`：SwiftUI GUI（Theme tokens + AppListView + LeftoverView）
- `Sources/mug-uninstaller-cli/`：CLI 入口
- `prototype/`：Python3 stdlib 原型（扫描规则与 Swift 版一致）
- `docs/design.md`：技术设计（扫描规则、平台坑、实测结论）
- `DESIGN.md`：GUI 设计规范（六节）

## 免责声明

本工具会删除文件（默认移入废纸篓，可恢复）。使用前请确认勾选内容，作者不对误删造成的损失负责。

## License

[MIT](LICENSE)
