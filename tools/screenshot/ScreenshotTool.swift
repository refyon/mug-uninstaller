// README 截图生成器：mock 数据 + 脱屏 NSHostingView + cacheDisplay → PNG。
// 说明：ImageRenderer 无法渲染 List(NSTableView)，会输出"禁止"兜底图；
// 改用真实脱屏窗口离屏捕获，可正确渲染包含 NSTableView 的视图。
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
                to: "docs/screenshots/main.png")

        // 2) 残留确认页（Chrome，演示高/中/低置信度）
        if let chrome = apps.first(where: { $0.bundleID == "com.google.Chrome" }) {
            let leftovers = LeftoverScanner.scan(bundleID: chrome.bundleID,
                                                 appName: chrome.displayName)
            capture(LeftoverView(app: chrome, initialResult: leftovers)
                        .frame(width: 720, height: 520),
                    size: NSSize(width: 720, height: 520),
                    to: "docs/screenshots/uninstall.png")
        }
        print("OK")
    }

    static func capture<V: View>(_ view: V, size: NSSize, to path: String) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)   // 挂到窗口服务器以获得正确 AppKit 渲染上下文

        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("位图失败 \(path)\n", stderr)
            exit(1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("PNG 失败 \(path)\n", stderr)
            exit(1)
        }
        try! png.write(to: URL(fileURLWithPath: path))
        window.close()
        print("已生成 \(path)（\(rep.pixelsWide)x\(rep.pixelsHigh)）")
    }
}
