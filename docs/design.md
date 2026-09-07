# macOS 应用卸载工具（类 Geek）设计文档

> 状态：✅ 核心目标达成——扫描/卸载/安全删除全链路实现，端到端实测通过（自建测试应用 0 失败全清除）；GUI 已打包为 .app 并启动。遗留：Developer ID 公证分发（需开发者账号）、root 文件删除路径与 GUI 交互待人工验收。

## 一、核心差异

Windows Geek 依赖注册表卸载项；macOS 无统一注册表，卸载 = 删除 `.app` + 清理散布文件。信息源：

1. `Info.plist` 的 `CFBundleIdentifier`（主匹配键）
2. pkg 回执 `/var/db/receipts/*.bom`、`/Library/Receipts/InstallHistory.plist`（pkgutil 可列全部安装文件）
3. Homebrew cask 元数据（`brew uninstall --cask --zap`）
4. 约定残留目录（见扫描引擎规则）

## 二、技术选型

- **Swift + SwiftUI，非沙盒应用**；不能上 MAS（沙盒限制），Developer ID 签名 + 公证后独立分发。
- CLI 原型（本项目）→ GUI 包装：MugUninstallerKit 库复用同一套扫描逻辑。
- 本机约束：仅 CommandLineTools（无 Xcode），SPM 构建可用；GUI 阶段需 Xcode 或手工 .app 打包。

## 三、分步计划

- [x] Step 1 应用扫描：/Applications、~/Applications；bundle id/名称/版本/来源(MAS/brew-cask/pkg)/运行状态/SIP 标记
- [x] Step 3 残留扫描引擎：规则路径 + 置信度分级（high/medium/low）——已验证，见「八、原型验证结论」
- [x] Step 2 卸载执行：退进程 → bootout → pkgutil --forget → 废纸篓（Python 与 Swift `uninstall` 干跑均验证：ToDesk 19 步计划全对）
- [x] Step 4 安全删除：白名单守卫、先 bootout 再删、废纸篓优先、root 文件走 osascript 管理员提权（**实际执行待端到端测试**）
- [x] Step 5 GUI：SwiftUI 已编译并启动（AppListView + LeftoverView 勾选确认 + FDA 探针），待交互验收
- [x] GUI 重设计（dsh-ui-taste 插件）：DESIGN.md 六节规范 + Theme.swift tokens（中性灰+绿色点缀、跟随系统明暗），视图无硬编码颜色/间距
- [ ] Step 6 FDA 权限引导（探针法检测）、签名公证、DMG 分发

## 四、扫描规则（MugUninstallerKit.LeftoverScanner）

| 位置 | 匹配 | 置信度 |
|---|---|---|
| ~/Library/{Caches,WebKit,HTTPStorages,Containers,Application Scripts}/<bid> | bundle id 精确 | high |
| ~/Library/Preferences/<bid>.plist、ByHost/<bid>.*、Saved Application State/<bid>.savedState、Cookies/<bid>.binarycookies | bundle id 精确 | high |
| ~/Library/Group Containers/<bid> 或 group.<bid> | 前缀 | high |
| LaunchAgents/LaunchDaemons（用户+系统） | plist Label 精确/前缀匹配 | high |
| ~/Library/Application Support/<名称> | 名称精确 | high |
| /Library/Application Support/<名称>、Caches/Logs/<名称>、PreferencePanes | 名称精确 | medium |
| /Library/PrivilegedHelperTools/<名称> | 名称精确 | high |
| 名称变体（去空格/-/_/小写）任意命中 | 模糊 | low |
| pkgutil --pkgs 中含 bid/名称的包回执 | 包含 | medium |

## 五、关键注意点

**权限/TCC**
- 非沙盒 + Full Disk Access 是前提；Containers、Group Containers、Safari、邮件等 TCC 保护区无 FDA 会静默漏扫/删失败。
- 只读扫描不需 FDA，删除受限目录才需要；按单次操作提权，勿整体 root。

**安全/误删**
- 名字碰撞（如第三方 Notes vs 系统备忘录）→ bundle id 优先，可疑项归"需确认"。
- 共享厂商目录（Adobe/Microsoft）删除前检查同厂商其他产品。
- 不跟随符号链接；删除路径限于已知残留目录白名单。
- SIP（/System/Applications）置灰不可删；系统扩展用 systemextensionsctl。

**平台细节**
- 大小写不敏感文件系统；APFS 快照/Time Machine 仍保留数据需告知；Keychain 无法枚举需提示手动。
- 多用户机器要扫所有用户的 ~/Library。

**流程**
- 先退 app 再删主包；先 bootout 再删 plist；删完二次复扫校验。

## 六、原型用法

```bash
cd apps/mug-uninstaller
python3 prototype/uninstaller_cli.py list                      # 列出已装应用
python3 prototype/uninstaller_cli.py scan <app路径|bundle id>   # 扫描残留
```

## 七、环境约束（已解决）

本机 CLT 16.2 (Intel, macOS 15.2) 三处损坏，修复方案：
1. **SDK 注解不匹配**（swiftinterface 为 swiftlang-6.0.3.1.5，编译器 6.0.3.1.10）→ `tools/fix-sdk.sh` 复制 SDK 到用户目录并批量修正注解，编译时 `-sdk tools/macos-sdk-patched`
2. **SwiftBridging 重复定义**（usr/include/swift 下 module.modulemap 与 bridging.modulemap 并存）→ 管理员改名禁用旧 module.modulemap（可逆）
3. **libPackageDescription 无导出符号**（SPM 清单无法链接）→ 本机绕过 SPM，`build.sh`/`build-gui.sh` 用 swiftc 两步静态库构建；Package.swift 留给正常环境
- App Store 的 Xcode 要求 macOS 26+，本机 15.2 Intel 装不了；Xcode 16.x 已不再提供。
- CLT 更新后需重跑 `tools/fix-sdk.sh`（编译器版本变则注解需同步修正）。

## 八、构建方式

正式构建全部由 GitHub Actions 完成（本机 CLT 损坏，仅用于代码编辑）：
- 推送/PR → `ci.yml` 编译 + CLI 冒烟测试
- 打 `v*` 标签 → `release.yml` 构建 arm64+x86_64 通用包、打包 .app 与 CLI、发布 Releases

本地替代（正常机器用 `swift build -c release`；本机损坏环境用）：

```bash
./build.sh          # CLI → .build/mug-uninstaller-cli
./build-gui.sh      # GUI → .build/mug-uninstaller（直接运行，无 .app 壳）
./package-gui.sh    # 打包 → .build/MugUninstaller.app
```

## 九、原型验证结论（实测发现）

真实应用验证（Firefox/ToDesk/Safari）：

1. **大小写不敏感文件系统**：名称变体匹配会重复列出同一路径（`Caches/Firefox` vs `Caches/firefox`）。
   去重键必须用 `os.path.realpath(path).lower()`；**`os.path.normcase` 在 POSIX/macOS 是恒等函数，不能用**。
2. **守护进程 label 未必等于 bid**：ToDesk 的 5 个 LaunchDaemons/Agents label 是
   `com.youqu.todesk.*`，而 bid 是 `com.youqu.todesk.mac` → 必须加「bid 去掉末段的 vendor.product 前缀」
   匹配（文件名与 plist Label 两种方式），否则漏掉全部守护进程（高危：卸载后残留服务）。
3. **PrivilegedHelperTools 需目录枚举**：helper 名如 `com.youqu.todesk.UninstallerHelper`，名称变体匹配不到。
4. **root 所有文件（如 root:staff 700 的 ~/Library/Logs/ToDesk）**：du 失败 ≠ 不存在，显示为
   「- (需管理员)」，删除时需提权（印证 Step4 设计）。
5. **SIP 检测**：`/Applications/Safari.app` 是 firmlink，realpath 指向
   `/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app`，判断用 `"/System/Applications" in realpath`。
6. pkg 回执：`pkgutil --pkgs` 无需 root 即可列出；`/var/db/receipts` 本机可读，扫描时可直接呈现回执文件。
