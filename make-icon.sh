#!/bin/bash
# 生成应用图标（accent 绿 squircle + 白色 trash 符号）→ Resources/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
# 正常机器直接用默认 SDK；本机（损坏 CLT）自动启用修补 SDK。
SDK_ARGS=()
[ -d "$ROOT/tools/macos-sdk-patched" ] && SDK_ARGS=(-sdk "$ROOT/tools/macos-sdk-patched")
mkdir -p .build
swiftc -O "${SDK_ARGS[@]}" make-icon.swift -o .build/make-icon
.build/make-icon
