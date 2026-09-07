#!/bin/bash
# 本地构建：CLT 编译器 + 修补版 SDK（版本注解 swiftlang-6.0.3.1.5 → 6.0.3.1.10）。
#
# 背景：本机 CLT 16.2 (Intel) 损坏三处——
#   1. SDK swiftinterface 注解(1.5) 与编译器(1.10)不匹配 → 编译报 "SDK is not supported"
#   2. /usr/include/swift 下 module.modulemap 与 bridging.modulemap 重复定义 SwiftBridging
#   3. libPackageDescription.dylib 无导出符号 → SPM 清单无法链接，swift build 不可用
# 本机装不了 Xcode（App Store 版要求 macOS 26+，本机 15.2 Intel）。
#
# 修复方式：
#   1. tools/fix-sdk.sh 生成修补版 SDK（tools/macos-sdk-patched）
#   2. 旧 module.modulemap 已由管理员改名为 module.modulemap.disabled
#   3. SPM 不可用 → 本项目零依赖，直接 swiftc 编译（Package.swift 留给正常环境）
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
# 正常机器（完整 Xcode）直接用默认 SDK；本机（损坏 CLT）自动启用修补 SDK。
SDK_ARGS=()
if [ -d "$ROOT/tools/macos-sdk-patched" ]; then
  SDK_ARGS=(-sdk "$ROOT/tools/macos-sdk-patched")
fi
mkdir -p .build
# 1) MugUninstallerKit → 静态库 + swiftmodule（保留 import 结构）
swiftc -O "${SDK_ARGS[@]}" -emit-library -static \
  -emit-module -module-name MugUninstallerKit -emit-module-path .build/MugUninstallerKit.swiftmodule \
  Sources/MugUninstallerKit/Support.swift \
  Sources/MugUninstallerKit/AppScanner.swift \
  Sources/MugUninstallerKit/LeftoverScanner.swift \
  Sources/MugUninstallerKit/UninstallEngine.swift \
  -o .build/libMugUninstallerKit.a
# 2) CLI 链接
swiftc -O "${SDK_ARGS[@]}" -I .build \
  Sources/mug-uninstaller-cli/main.swift .build/libMugUninstallerKit.a \
  -o .build/mug-uninstaller-cli
echo "OK: .build/mug-uninstaller-cli"
