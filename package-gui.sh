#!/bin/bash
# 打包 GUI 为可双击的 .app（ad-hoc 签名，本机使用；正式分发需 Developer ID + 公证）。
# 依赖 build-gui.sh 已产出 .build/mug-uninstaller。
set -euo pipefail
cd "$(dirname "$0")"
[ -f .build/mug-uninstaller ] || { echo "先运行 ./build-gui.sh"; exit 1; }
APP=.build/MugUninstaller.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/mug-uninstaller "$APP/Contents/MacOS/mug-uninstaller"
# 应用图标（缺失时自动生成）
[ -f Resources/AppIcon.icns ] || ./make-icon.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>MugUninstaller</string>
	<key>CFBundleDisplayName</key><string>Mug Uninstaller</string>
	<key>CFBundleIdentifier</key><string>com.emonyr.mug-uninstaller</string>
	<key>CFBundleExecutable</key><string>mug-uninstaller</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF
codesign --force -s - "$APP" 2>/dev/null || echo "警告: codesign 失败（不影响本地双击运行）"
echo "OK: $APP"
