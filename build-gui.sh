#!/bin/bash
# 构建 SwiftUI GUI（依赖 build.sh 先产出 libMugUninstallerKit.a + swiftmodule）。
# SPM 在本机不可用（libPackageDescription 损坏），直接 swiftc 编译。
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
# 正常机器直接用默认 SDK；本机（损坏 CLT）自动启用修补 SDK。
SDK_ARGS=()
[ -d "$ROOT/tools/macos-sdk-patched" ] && SDK_ARGS=(-sdk "$ROOT/tools/macos-sdk-patched")
[ -f .build/libMugUninstallerKit.a ] || { echo "先运行 ./build.sh"; exit 1; }
mkdir -p .build
swiftc -O "${SDK_ARGS[@]}" -parse-as-library -I .build \
  Sources/mug-uninstaller/Theme.swift \
  Sources/mug-uninstaller/MugUninstallerApp.swift \
  Sources/mug-uninstaller/AppListView.swift \
  Sources/mug-uninstaller/LeftoverView.swift \
  .build/libMugUninstallerKit.a \
  -o .build/mug-uninstaller
echo "OK: .build/mug-uninstaller"
