#!/bin/bash
# 生成 README 截图：mock 数据 + SwiftUI ImageRenderer 离屏渲染（无需屏幕录制权限）。
# 依赖 build.sh 已产出 libMugUninstallerKit.a。
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
SDK_ARGS=()
[ -d "$ROOT/tools/macos-sdk-patched" ] && SDK_ARGS=(-sdk "$ROOT/tools/macos-sdk-patched")
[ -f .build/libMugUninstallerKit.a ] || { echo "先运行 ./build.sh"; exit 1; }
mkdir -p .build
swiftc -O "${SDK_ARGS[@]}" -parse-as-library -I .build \
  Sources/mug-uninstaller/Theme.swift \
  Sources/mug-uninstaller/AppListView.swift \
  Sources/mug-uninstaller/LeftoverView.swift \
  tools/screenshot/ScreenshotTool.swift \
  .build/libMugUninstallerKit.a \
  -o .build/screenshot-tool
.build/screenshot-tool
