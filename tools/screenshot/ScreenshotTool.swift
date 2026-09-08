// README 截图生成器：mock 数据 + 脱屏 NSHostingView + cacheDisplay 渲染内容，
// 再合成 macOS 窗口框（标题栏 + 红绿灯 + 圆角），输出带透明边距的 PNG。
// ImageRenderer 无法渲染 List(NSTableView)，须走脱屏真实窗口捕获。
// 无需屏幕录制权限；仅工具进程内启用 mock 开关，不影响正式应用。
import AppKit
import SwiftUI
import MugUninstallerKit

@main
struct ScreenshotTool {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        AppScanner.isMocking = true
        LeftoverScanner.isMocking = true
        try? FileManager.default.createDirectory(atPath: "docs/screenshots",
                                                 withIntermediateDirectories: true)

        // 1) 主窗口（默认隐藏系统应用）
        let apps = AppScanner.scan()
        capture(AppListView(initialApps: apps).frame(width: 800, height: 520),
                size: NSSize(width: 800, height: 520),
                title: "Mug Uninstaller",
                to: "docs/screenshots/main.png")

        // 2) 残留确认页（Chrome，演示高/中/低置信度）
        if let chrome = apps.first(where: { $0.bundleID == "com.google.Chrome" }) {
            let leftovers = LeftoverScanner.scan(bundleID: chrome.bundleID,
                                                 appName: chrome.displayName)
            capture(LeftoverView(app: chrome, initialResult: leftovers)
                        .frame(width: 720, height: 520),
                    size: NSSize(width: 720, height: 520),
                    title: "卸载 Chrome",
                    to: "docs/screenshots/uninstall.png")
        }
        print("OK")
    }

    /// 渲染视图内容并合成 macOS 窗口框后写 PNG。
    static func capture<V: View>(_ view: V, size: NSSize, title: String, to path: String) {
        // 1) 内容区渲染（真实窗口上下文，能画 NSTableView）
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("位图失败 \(path)\n", stderr); exit(1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.close()

        let contentImage = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        contentImage.addRepresentation(rep)

        // 2) 合成 macOS 窗框（浅色主题）
        let pad: CGFloat = 48        // 四周透明边距（圆角/影子视觉空间）
        let barH: CGFloat = 28       // 标题栏高度
        let radius: CGFloat = 10     // 窗口圆角
        let cw = size.width
        let ch = size.height
        let out = NSImage(size: NSSize(width: cw + pad * 2, height: ch + barH + pad * 2),
                          flipped: false) { rect in
            let w = rect.width, h = rect.height
            // 透明背景
            NSColor.clear.set()
            rect.fill()

            // 窗口底（浅灰，与内容顶部背景衔接）
            let winTop = rect.maxY - pad            // 窗口顶部 y
            let winRect = NSRect(x: pad, y: pad, width: cw, height: ch + barH)
            let winPath = NSBezierPath(roundedRect: winRect, xRadius: radius, yRadius: radius)
            NSColor(calibratedWhite: 0.93, alpha: 1).setFill()  // 近似 windowBackground 浅色
            winPath.fill()

            // 标题栏居中文字
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1),
            ]
            let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
            let tsz = titleStr.size()
            titleStr.draw(at: NSPoint(x: w / 2 - tsz.width / 2,
                                      y: winTop - barH / 2 - tsz.height / 2))

            // 红绿灯
            let lights: [NSColor] = [
                NSColor(red: 1.00, green: 0.37, blue: 0.34, alpha: 1),
                NSColor(red: 1.00, green: 0.74, blue: 0.18, alpha: 1),
                NSColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1),
            ]
            let lightCY = winTop - barH / 2
            for (i, c) in lights.enumerated() {
                c.setFill()
                NSBezierPath(ovalIn: NSRect(x: pad + 14 + CGFloat(i) * 20 - 6,
                                            y: lightCY - 6, width: 12, height: 12)).fill()
            }

            // 内容区（底部）
            contentImage.draw(in: NSRect(x: pad, y: pad, width: cw, height: ch))
            return true
        }

        guard let tiff = out.tiffRepresentation,
              let outRep = NSBitmapImageRep(data: tiff),
              let png = outRep.representation(using: .png, properties: [:]) else {
            fputs("PNG 失败 \(path)\n", stderr); exit(1)
        }
        try! png.write(to: URL(fileURLWithPath: path))
        print("已生成 \(path)（\(outRep.pixelsWide)x\(outRep.pixelsHigh)）")
    }
}
